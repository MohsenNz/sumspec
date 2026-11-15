{-# LANGUAGE OverloadedStrings #-}

-- | Golden tests over two corpora of spec files.
--
-- test/parse/: the golden file next to each case holds the spec printed
-- back in canonical form, or the parse error.
-- test/check/: the golden file holds "OK", or the type errors.
-- test/model/: the golden file holds the model of the spec (see
-- 'renderModel'), built from the definitions that parse.
-- Agreement: in every spec the checker accepts, every path resolves in
-- the model, and the strict rule ('step') reads it as the lenient
-- resolver does.
-- The example specs in example/ are cases in both, with their golden
-- files in those directories.
--
-- Run with @cabal test --test-options=--accept@ to regenerate, then
-- review the diff before committing.
module Main (main) where

import Data.ByteString.Lazy qualified as LBS
import Data.Foldable (toList)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Map.Strict qualified as M
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as T
import Data.Text.IO qualified as T
import SumSpec
import System.FilePath (replaceExtension, takeBaseName, (</>))
import Test.Tasty (TestTree, defaultMain, testGroup)
import Test.Tasty.Golden (findByExtension, goldenVsString)
import Test.Tasty.HUnit (assertFailure, testCase)

main :: IO ()
main = do
  parseCases <- corpus "test/parse"
  checkCases <- corpus "test/check"
  modelCases <- corpus "test/model"
  defaultMain $
    testGroup
      "sumspec"
      [ testGroup "parse" [golden parseOnce c | c <- parseCases]
      , testGroup "round trip" [golden parseTwice c | c <- parseCases]
      , testGroup "check" [goldenIO check c | c <- checkCases]
      , testGroup "model" [goldenIO modelOf c | c <- modelCases]
      , testGroup "model agrees with the checker" [agreement file | (file, _) <- checkCases]
      ]

-- | Each case is a spec file and its golden file. The example specs are
-- cases in every corpus, with golden files named @example-<name>.golden@.
corpus :: FilePath -> IO [(FilePath, FilePath)]
corpus dir = do
  files <- findByExtension [".sumspec"] dir
  pure $
    [(file, dir </> "example-" <> takeBaseName file <> ".golden") | file <- examples]
      <> [(file, replaceExtension file ".golden") | file <- files]

examples :: [FilePath]
examples =
  [ "example/drone.sumspec"
  , "example/todomvc.sumspec"
  , "example/git.sumspec"
  , "example/todo-core.sumspec"
  , "example/todo-ui.sumspec"
  , "parvaz/parvaz-core.sumspec"
  ]

golden :: (FilePath -> Text -> Text) -> (FilePath, FilePath) -> TestTree
golden run (file, goldenFile) =
  goldenVsString (takeBaseName file) goldenFile $
    LBS.fromStrict . T.encodeUtf8 . run file <$> T.readFile file

-- | A golden test whose output reads more files than the case: the bases
-- a spec imports.
goldenIO :: (FilePath -> IO Text) -> (FilePath, FilePath) -> TestTree
goldenIO run (file, goldenFile) =
  goldenVsString (takeBaseName file) goldenFile $
    LBS.fromStrict . T.encodeUtf8 <$> run file

-- | The canonical form of the spec, or the parse error.
parseOnce :: FilePath -> Text -> Text
parseOnce file source =
  either (T.pack . renderParseError) renderSpec (parseSpec file source)

-- | Parses the canonical form again. It must print the same, so this
-- test shares the golden file of 'parseOnce'.
parseTwice :: FilePath -> Text -> Text
parseTwice file source = case parseSpec file source of
  Left err -> T.pack (renderParseError err)
  Right spec -> parseOnce file (renderSpec spec)

-- | "OK", or the type errors (or the parse error, if it doesn't parse).
-- The bases the spec imports are loaded from their files.
check :: FilePath -> IO Text
check file = do
  Loaded source parsed imports <- loadSpec file
  pure $ case parsed of
    Left err -> T.pack (renderParseError err)
    Right spec -> case checkSpecWith imports file source spec of
      [] -> T.pack "OK\n"
      errors -> T.pack (renderCheckErrors source errors)

-- | The model of the definitions that parse, with the bases they import,
-- or the parse error of the header.
modelOf :: FilePath -> IO Text
modelOf file = do
  source <- T.readFile file
  case parseSpecPartial file source of
    Left err -> pure (T.pack (renderParseError err))
    Right (spec, _) -> do
      imports <- loadImports file spec
      pure (renderModel (modelWith (importedBases imports) spec))

-- | In a spec the checker accepts, every path resolves in the model with
-- nothing unknown; and from a type, the strict rule ('step') accepts each
-- name after the head and finds the variant the lenient resolver finds.
-- A spec with errors, or that doesn't parse, is skipped.
agreement :: FilePath -> TestTree
agreement file = testCase (takeBaseName file) $ do
  Loaded source parsed imports <- loadSpec file
  case parsed of
    Right spec
      | not (hasErrors (checkSpecWith imports file source spec)) ->
          case concatMap (disagreement (modelWith (importedBases imports) spec)) (specPaths spec) of
            [] -> pure ()
            problems -> assertFailure (T.unpack (T.unlines problems))
    _ -> pure ()

disagreement :: Model -> NonEmpty Name -> [Text]
disagreement m p@(h :| rest) =
  [problem "doesn't resolve" | any (isUnknown . snd) refs]
    <> case M.lookup (nameText h) (modelTypes m) of
      Just t -> strict (typeInfoBody t) rest (drop 1 refs)
      Nothing -> []
  where
    (refs, _) = resolvePath m p
    written = T.intercalate "." (map nameText (toList p))
    problem what = written <> " " <> what
    strict _ [] _ = []
    strict here (n : ns) rs = case (step m here n, rs) of
      (Right (v, payload), (_, RefVariant v') : rs')
        | variantName (variantInfo v) == variantName (variantInfo v') ->
            strict payload ns rs'
      (Right _, _) -> [problem ("reads " <> nameText n <> " otherwise than step")]
      (Left _, _) -> [problem ("is rejected by step at " <> nameText n)]
    isUnknown = \case
      RefUnknown -> True
      _ -> False

-- | Every path written in a spec, with the alternatives of @S.{A | B}@
-- each a path from @S@.
-- Named patterns are expanded, so every use is read in its body.
specPaths :: Spec -> [NonEmpty Name]
specPaths spec = concatMap definition (specDefinitions (expansionSpec (expandSpec spec)))
  where
    definition = \case
      DefType _ -> []
      DefPattern _ -> []
      DefConst (ConstDef _ ty value) -> case value of
        ConstVariant v -> [ty :| [v]]
        ConstLiteral _ _ -> []
      DefInit _ p -> pattern p
      DefEvent (Event _ input transitions) ->
        concatMap pattern (toList input)
          <> concat
            [ [q | Shared q _ <- shared]
                <> concatMap pattern (toList from <> toList to)
                <> maybe [] guardPaths guard
            | Transition shared branches <- toList transitions
            , Branch from guard to _ _ <- toList branches
            ]
    pattern = \case
      PatternPath p args -> p : concatMap pattern args
      PatternElement p _ args -> p : concatMap pattern args
      PatternAlts p alts -> concatMap (alternative p) alts
      PatternNamed p _ -> pattern p
      PatternPrimed _ p -> pattern p
      _ -> []
    alternative (h :| rest) = \case
      PatternPath q args -> (h :| (rest <> toList q)) : concatMap pattern args
      PatternAlts q alts -> concatMap (alternative (h :| (rest <> toList q))) alts
      PatternNamed q _ -> alternative (h :| rest) q
      PatternPrimed _ q -> alternative (h :| rest) q
      q -> pattern q
    guardPaths = \case
      GuardPattern p -> pattern p
      GuardCompare _ a b -> concatMap operand [a, b]
      GuardIn a _ -> operand a
      GuardNot g -> guardPaths g
      GuardAnd gs -> concatMap guardPaths gs
      GuardOr gs -> concatMap guardPaths gs
    operand = \case
      OperandVariant p -> [p]
      _ -> []
