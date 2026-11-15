{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

-- | What hovering over a name shows: its definition, printed, and the
-- comments written beside it in the source.
module SumSpec.Lsp.Hover
  ( hover
  , docComment
  , eventValues
  ) where

import Data.Foldable (toList)
import Data.List (find)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Map.Strict qualified as M
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Language.LSP.Protocol.Types
  ( Hover (..)
  , MarkupContent (..)
  , MarkupKind (..)
  , type (|?) (..)
  )
import SumSpec.Expand (expandPatternIn)
import SumSpec.Lsp.Index (Kind (..), Occurrence (..))
import SumSpec.Lsp.Position (nameRange)
import SumSpec.Model
import SumSpec.Pretty (renderAtomic, renderDefinition, renderPattern)
import SumSpec.Syntax
import Text.Megaparsec (SourcePos (..), unPos)

-- | The hover for the name under the cursor: what it refers to, as
-- markdown. 'Nothing' when it doesn't resolve. The function gives the
-- source of the file a position is in: a base's names are in its file.
hover :: Text -> (SourcePos -> Text) -> Spec -> Model -> Occurrence -> Maybe Hover
hover source sourceAt spec m occ = do
  target <- occTarget occ
  body <- describe source spec m (occKind occ) (occName occ) target
  -- A value's line is a transition: its comment isn't about the value.
  let docs
        | occKind occ == KValue = []
        | otherwise = toList (docComment (sourceAt (namePos target)) (namePos target))
  pure
    Hover
      { _contents =
          InL (MarkupContent MarkupKind_Markdown (T.intercalate "\n\n" (body <> docs)))
      , _range = Just (nameRange source (occName occ))
      }

-- | The paragraphs that describe a definition, before its comments.
describe :: Text -> Spec -> Model -> Kind -> Name -> Name -> Maybe [Text]
describe source spec m kind occName' target = case kind of
  KType -> do
    t <- M.lookup (nameText target) (modelTypes m)
    pure . (: []) . code $ case M.lookup (nameText target) (modelAtomics m) of
      Just a -> renderAtomic a
      Nothing ->
        maybe
          (nameText target)
          (renderDefinition . DefType)
          (M.lookup (nameText (typeInfoName t)) (modelTypeDefs m))
  KVariant -> do
    v <-
      find
        ((== target) . variantName . variantInfo)
        ( M.findWithDefault [] (nameText target) (modelVariants m)
            <> M.findWithDefault [] (nameText target) (modelBaseVariants m)
        )
    let
      Variant n payload _ = variantInfo v
      written = variantOwnerPath v <> "." <> nameText n
    pure
      [ code (written <> maybe "" (const " ...") payload)
      , "Variant of `"
          <> variantOwnerPath v
          <> "`"
          <> maybe "" (const ", with a payload") payload
          <> "."
      ]
  KConst -> do
    c <- M.lookup (nameText target) (modelConsts m)
    pure [code (renderDefinition (DefConst c))]
  KEvent -> do
    e <-
      maybe
        (M.lookup (nameText target) (modelBaseEvents m))
        Just
        (M.lookup (nameText target) (modelEvents m))
    let
      Event n input transitions = eventInfo e
      count = sum (map (length . transitionBranches) (toList transitions))
    pure $
      [ code (nameText n <> maybe "" ((" " <>) . renderPattern) input)
      , "Event with "
          <> T.pack (show count)
          <> (if count == 1 then " transition." else " transitions.")
      ]
        <> ["Not listed in `__events`." | not (eventListed e)]
        -- The comment beside its entry in __events.
        <> toList
          ( do
              entry <- find ((== nameText n) . nameText) (specEvents spec)
              docComment source (namePos entry)
          )
  KPattern -> do
    d <- M.lookup (nameText target) (modelPatterns m)
    let params = length (patternDefParams d)
    pure $
      [ code (renderDefinition (DefPattern d))
      , "Named pattern"
          <> ( if params == 0
                 then ""
                 else
                   " with "
                     <> T.pack (show params)
                     <> (if params == 1 then " parameter" else " parameters")
             )
          <> "."
      ]
        -- At a use, what it stands for.
        <> [ "Expands to:\n\n" <> code (renderPattern (expandPatternIn spec p))
           | Just p <- [patternUse spec occName']
           ]
  KPath -> do
    d <- M.lookup (nameText target) (modelPaths m)
    pure [code (renderDefinition (DefPath d)), "Named shared path."]
  KAnnotation -> pure [code ("@" <> nameText target)]
  KQualifier -> do
    b <- M.lookup (nameText target) (modelImports m)
    pure
      [ code (nameText target <> " \"" <> T.pack (baseInfoFile b) <> "\"")
      , "Base spec, in `__imports`"
          <> maybe "" (\r -> ", whose root is `" <> nameText r <> "`") (baseInfoRoot b)
          <> "."
      ]
  KValue ->
    pure
      [ code (nameText target <> maybe "" ((" : " <>) . patternType) bound)
      , "A value of this transition."
      ]
    where
      bound =
        lookup
          target
          [ (x, p)
          | DefEvent e <- specDefinitions spec
          , (x, Just p) <- eventValues e
          ]
  where
    code t = "```sumspec\n" <> t <> "\n```"
    patternType = \case
      PatternPath p _ -> path p
      PatternElement p _ _ -> path p
      PatternAlts p _ -> path p
      p -> renderPattern p
    path = T.intercalate "." . map nameText . toList

-- | The use of a named pattern whose head is this name, as written: with
-- its arguments, or alone as a shared path.
patternUse :: Spec -> Name -> Maybe Pattern
patternUse spec n = find ((== Just n) . useHead) (concatMap definition (specDefinitions spec))
  where
    useHead = \case
      PatternPath (h :| []) _ -> Just h
      PatternApply (h :| []) _ -> Just h
      _ -> Nothing
    definition = \case
      DefInit _ p -> pattern p
      DefPattern d -> pattern (patternDefBody d)
      DefEvent (Event _ input transitions) ->
        concatMap pattern (toList input)
          <> concat
            [ [PatternPath (h :| []) [] | Shared (h :| []) Nothing <- paths]
                <> concatMap pattern (toList from <> toList to)
                <> maybe [] guardPatterns g
                <> concat [concatMap pattern args | Dispatch _ args <- toList d]
            | Transition paths branches <- toList transitions
            , Branch from g to _ d <- toList branches
            ]
      _ -> []
    pattern p =
      p : case p of
        PatternPath _ args -> concatMap pattern args
        PatternApply _ groups -> concatMap (concatMap pattern) groups
        PatternElement _ _ args -> concatMap pattern args
        PatternAlts _ alts -> concatMap pattern alts
        PatternNamed q _ -> pattern q
        PatternPrimed _ q -> pattern q
        _ -> []
    guardPatterns = \case
      GuardPattern p -> pattern p
      GuardNot g -> guardPatterns g
      GuardAnd gs -> concatMap guardPatterns gs
      GuardOr gs -> concatMap guardPatterns gs
      _ -> []

-- | The values an event names, in its input and its transitions: @#x@
-- with the pattern it names (@T#x@), or none for @Head(#x)@.
eventValues :: Event -> [(Name, Maybe Pattern)]
eventValues (Event _ input transitions) =
  concatMap pattern (toList input)
    <> concat
      [ concatMap pattern (toList from)
          <> concatMap pattern (toList to)
          <> maybe [] guardValues guard
      | Transition _ branches <- toList transitions
      , Branch from guard to _ _ <- toList branches
      ]
  where
    pattern = \case
      PatternPath _ args -> concatMap pattern args
      PatternElement _ _ args -> concatMap pattern args
      PatternNamed p x -> (x, Just p) : pattern p
      PatternBound x -> [(x, Nothing)]
      PatternAlts _ alts -> concatMap pattern alts
      PatternApply _ groups -> concatMap (concatMap pattern) groups
      PatternPrimed _ p -> pattern p
      PatternList {} -> []
      PatternName _ -> []
      PatternExpr _ -> []
    guardValues = \case
      GuardPattern p -> pattern p
      GuardNot g -> guardValues g
      GuardAnd gs -> concatMap guardValues gs
      GuardOr gs -> concatMap guardValues gs
      GuardCompare {} -> []
      GuardIn {} -> []

-- | The comments written about the definition at this position: the
-- comment lines just above it, at its indentation, and the comment after
-- it on its line, with the comment lines under that one at the same
-- column. 'Nothing' when there are none.
docComment :: Text -> SourcePos -> Maybe Text
docComment source pos =
  case above <> trailing of
    [] -> Nothing
    ls -> Just (T.unlines ls)
  where
    sourceLines = T.lines source
    lineNo = unPos (sourceLine pos) - 1
    line = fromMaybe "" (lookup lineNo (zip [0 ..] sourceLines))
    indent = T.takeWhile (== ' ') line
    above =
      reverse
        [ stripDashes l
        | l <-
            takeWhile
              (\l -> T.takeWhile (== ' ') l == indent && isComment l)
              (reverse (take lineNo sourceLines))
        ]
    -- The comment after the definition, and its column.
    (column, rest) = T.breakOn "--" line
    trailing
      | T.null rest || T.all (== ' ') column = []
      | otherwise =
          stripDashes rest
            : [ stripDashes l
              | l <-
                  takeWhile
                    (\l -> isComment l && T.length (T.takeWhile (== ' ') l) == T.length column)
                    (drop (lineNo + 1) sourceLines)
              ]
    isComment l = "--" `T.isPrefixOf` T.stripStart l
    stripDashes = T.strip . T.dropWhile (== '-') . T.stripStart
