{-# LANGUAGE OverloadedStrings #-}

-- | The SumSpec language server, run as @sumspec lsp@ over stdio.
--
-- It publishes diagnostics each time a document is opened, changed or
-- saved, and answers the outline, go to definition, references, hover,
-- completion and semantic highlighting. Each request parses the document as it is in
-- the editor; a document with parse errors still gives the definitions
-- that parsed. See docs/lsp.md.
module SumSpec.Lsp
  ( runLanguageServer
  , serverDefinition
  , diagnose
  ) where

import Control.Monad.IO.Class (liftIO)
import Data.List.NonEmpty qualified as NE
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as M
import Data.Text (Text)
import Data.Text qualified as T
import Language.LSP.Diagnostics (partitionBySource)
import Language.LSP.Protocol.Message
import Language.LSP.Protocol.Types
import Language.LSP.Server
import Language.LSP.VFS (virtualFileText, virtualFileVersion)
import SumSpec
  ( Base (..)
  , CheckError (..)
  , Imported
  , Model
  , Name (..)
  , Severity (..)
  , Spec
  , checkSpecWith
  , importedBases
  , loadImports
  , modelWith
  , nameLocal
  , parseSpec
  , parseSpecPartial
  )
import SumSpec.Lsp.Completion (completions)
import SumSpec.Lsp.Hover (hover)
import SumSpec.Lsp.Index (Occurrence (..), occurrenceAt, occurrencesWith, symbols)
import SumSpec.Lsp.Position (nameRange, tokenRange)
import SumSpec.Lsp.Tokens (encodeSemanticTokens, semanticTokens)
import Text.Megaparsec
  ( ParseErrorBundle (..)
  , SourcePos (..)
  , attachSourcePos
  , errorOffset
  , parseErrorTextPretty
  )

-- | Runs the server on stdin and stdout; returns the exit code.
runLanguageServer :: IO Int
runLanguageServer = runServer serverDefinition

serverDefinition :: ServerDefinition ()
serverDefinition =
  ServerDefinition
    { parseConfig = \_ _ -> Right ()
    , onConfigChange = \_ -> pure ()
    , defaultConfig = ()
    , configSection = "sumspec"
    , doInitialize = \env _ -> pure (Right env)
    , staticHandlers = const handlers
    , interpretHandler = \env -> Iso (runLspT env) liftIO
    , options =
        defaultOptions
          { optTextDocumentSync = Just sync
          , optCompletionTriggerCharacters = Just ".@"
          }
    }
  where
    sync =
      TextDocumentSyncOptions
        { _openClose = Just True
        , _change = Just TextDocumentSyncKind_Incremental
        , _willSave = Nothing
        , _willSaveWaitUntil = Nothing
        , _save = Just (InR (SaveOptions (Just False)))
        }

-- | The library keeps every open document in its virtual file system; the
-- notification handlers only say when to diagnose it again.
handlers :: Handlers (LspM ())
handlers =
  mconcat
    [ notificationHandler SMethod_Initialized $ \_ -> pure ()
    , notificationHandler SMethod_TextDocumentDidOpen $ \msg ->
        let
          TNotificationMessage _ _ (DidOpenTextDocumentParams doc) = msg
          TextDocumentItem uri _ _ _ = doc
        in
          publish uri
    , notificationHandler SMethod_TextDocumentDidChange $ \msg ->
        let
          TNotificationMessage _ _ (DidChangeTextDocumentParams doc _) = msg
          VersionedTextDocumentIdentifier uri _ = doc
        in
          publish uri
    , notificationHandler SMethod_TextDocumentDidSave $ \msg ->
        let
          TNotificationMessage _ _ (DidSaveTextDocumentParams doc _) = msg
          TextDocumentIdentifier uri = doc
        in
          publish uri
    , notificationHandler SMethod_TextDocumentDidClose $ \msg ->
        let
          TNotificationMessage _ _ (DidCloseTextDocumentParams doc) = msg
          TextDocumentIdentifier uri = doc
        in
          publishDiagnostics maxDiagnostics (toNormalizedUri uri) Nothing mempty
    , notificationHandler SMethod_WorkspaceDidChangeConfiguration $ \_ -> pure ()
    , notificationHandler SMethod_SetTrace $ \_ -> pure ()
    , requestHandler SMethod_TextDocumentDocumentSymbol $ \req respond -> do
        let TRequestMessage _ _ _ (DocumentSymbolParams _ _ (TextDocumentIdentifier uri)) = req
        result <- document uri
        respond . Right $ case result of
          Just d -> InR (InL (symbols (docSource d) (docSpec d)))
          Nothing -> InR (InR Null)
    , requestHandler SMethod_TextDocumentDefinition $ \req respond -> do
        let TRequestMessage _ _ _ (DefinitionParams (TextDocumentIdentifier uri) pos _ _) = req
        result <- document uri
        respond . Right $ case result of
          Just d
            | Just occ <- occurrenceAt (docSource d) pos (docOccurrences d)
            , Just target <- occTarget occ ->
                InL (Definition (InL (location uri d target)))
          _ -> InR (InR Null)
    , requestHandler SMethod_TextDocumentReferences $ \req respond -> do
        let
          TRequestMessage _ _ _ (ReferenceParams (TextDocumentIdentifier uri) pos _ _ context) = req
          ReferenceContext includeDeclaration = context
        result <- document uri
        respond . Right $ case result of
          Just d
            | occs <- docOccurrences d
            , Just occ <- occurrenceAt (docSource d) pos occs
            , Just target <- occTarget occ ->
                InL
                  [ Location uri (nameRange (docSource d) (occName o))
                  | o <- occs
                  , occTarget o == Just target
                  , includeDeclaration || not (occDefinition o)
                  ]
          _ -> InR Null
    , requestHandler SMethod_TextDocumentSemanticTokensFull $ \req respond -> do
        let TRequestMessage _ _ _ (SemanticTokensParams _ _ (TextDocumentIdentifier uri)) = req
        result <- document uri
        respond . Right $ case result of
          Just d
            | Right tokens <-
                encodeSemanticTokens (semanticTokens (docSource d) (docOccurrences d)) ->
                InL tokens
          _ -> InR Null
    , requestHandler SMethod_TextDocumentHover $ \req respond -> do
        let TRequestMessage _ _ _ (HoverParams (TextDocumentIdentifier uri) pos _) = req
        result <- document uri
        respond . Right $ case result of
          Just d
            | Just occ <- occurrenceAt (docSource d) pos (docOccurrences d)
            , Just h <- hover (docSource d) (sourceAt d) (docSpec d) (docModel d) occ ->
                InL h
          _ -> InR Null
    , requestHandler SMethod_TextDocumentCompletion $ \req respond -> do
        let TRequestMessage _ _ _ (CompletionParams (TextDocumentIdentifier uri) pos _ _ _) = req
        result <- document uri
        respond . Right $ case result of
          Just d -> InL (completions (docSource d) (sourceAt d) (docSpec d) (docModel d) pos)
          Nothing -> InR (InR Null)
    ]

-- | An open document: its text as it is in the editor now, the spec parsed
-- from it (only the definitions that parse, when some don't), its model
-- with the bases it imports, and the text of each file a name may be in.
data Document = Document
  { docSource :: Text
  , docSpec :: Spec
  , docModel :: Model
  , docOccurrences :: [Occurrence]
  , docSources :: Map FilePath Text
  }

-- | The document at this URI. The bases it imports are read from their
-- files. 'Nothing' when the document isn't open or its header doesn't
-- parse.
document :: Uri -> LspM () (Maybe Document)
document uri =
  getVirtualFile (toNormalizedUri uri) >>= \case
    Nothing -> pure Nothing
    Just file -> do
      let source = virtualFileText file
      case parseSpecPartial (uriPath uri) source of
        Left _ -> pure Nothing
        Right (spec, _) -> do
          bases <- importedBases <$> liftIO (loadImports (uriPath uri) spec)
          let m = modelWith bases spec
          pure . Just $
            Document
              { docSource = source
              , docSpec = spec
              , docModel = m
              , docOccurrences = occurrencesWith m spec
              , docSources = M.fromList ((uriPath uri, source) : concatMap sources bases)
              }
  where
    sources b = (baseFile b, baseSource b) : concatMap sources (baseBases b)

-- | The source of the file a position is in: the document's, or a base's.
sourceAt :: Document -> SourcePos -> Text
sourceAt d pos = M.findWithDefault (docSource d) (sourceName pos) (docSources d)

-- | Where a name is: in the document, or in a base's file.
location :: Uri -> Document -> Name -> Location
location uri d n
  | file == uriPath uri || M.notMember file (docSources d) =
      Location uri (nameRange (docSource d) n)
  | otherwise =
      -- Written in the base without its qualifier: Core, not core.Core.
      Location
        (filePathToUri file)
        (nameRange (sourceAt d (namePos n)) n {nameText = nameLocal (nameText n)})
  where
    file = sourceName (namePos n)

-- | The file path of a URI, for error messages; the URI itself when it
-- isn't a file.
uriPath :: Uri -> FilePath
uriPath uri = maybe (T.unpack (getUri uri)) id (uriToFilePath uri)

-- | Diagnoses the document at this URI, as it is in the editor now.
publish :: Uri -> LspM () ()
publish uri = do
  let nuri = toNormalizedUri uri
  getVirtualFile nuri >>= \case
    Nothing -> pure ()
    Just file -> do
      let source = virtualFileText file
      imports <- case parseSpec (uriPath uri) source of
        Right spec -> liftIO (loadImports (uriPath uri) spec)
        Left _ -> pure []
      publishDiagnostics
        maxDiagnostics
        nuri
        (Just (virtualFileVersion file))
        (partitionBySource (diagnoseWith imports (uriPath uri) source))

maxDiagnostics :: Int
maxDiagnostics = 100

-- | The diagnostics of a document: every parse error, or else every error
-- and warning of the checker. While the document has parse errors, the
-- checker isn't run: its errors would be about the definitions missing.
diagnose :: FilePath -> Text -> [Diagnostic]
diagnose = diagnoseWith []

-- | 'diagnose' for a document with imports, given what the loader found at
-- each (see 'loadImports').
diagnoseWith :: [Imported] -> FilePath -> Text -> [Diagnostic]
diagnoseWith imports path source = case parseSpec path source of
  Left bundle ->
    [ diagnostic DiagnosticSeverity_Error pos (T.strip (T.pack (parseErrorTextPretty e)))
    | (e, pos) <-
        NE.toList . fst $
          attachSourcePos errorOffset (bundleErrors bundle) (bundlePosState bundle)
    ]
  Right spec ->
    [ diagnostic (severity (errorSeverity e)) (errorPos e) (errorMessage e)
    | e <- checkSpecWith imports path source spec
    ]
  where
    severity = \case
      Error -> DiagnosticSeverity_Error
      Warning -> DiagnosticSeverity_Warning
    diagnostic sev pos message =
      Diagnostic
        { _range = tokenRange source pos
        , _severity = Just sev
        , _code = Nothing
        , _codeDescription = Nothing
        , _source = Just "sumspec"
        , _message = message
        , _tags = Nothing
        , _relatedInformation = Nothing
        , _data_ = Nothing
        }
