{-# LANGUAGE OverloadedStrings #-}

-- | Reads a spec and the base specs it imports (see "Layered specs" in
-- spec/spec-v1.md). Each import's file is found relative to the importing
-- file, read, parsed and checked on its own, with its own imports, before
-- the importing spec is checked against it. Nothing here throws for an
-- import: a file that can't be read, doesn't parse or makes a cycle is an
-- 'ImportResult' the checker reports on its entry in @__imports@.
module SumSpec.Load
  ( Loaded (..)
  , loadSpec
  , loadImports
  , importedBases
  ) where

import Control.Exception (IOException, try)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as T
import SumSpec.Check
  ( ImportResult (..)
  , Imported (..)
  , checkSpecWith
  , hasErrors
  )
import SumSpec.Model (Base (..))
import SumSpec.Parser (ParseError, parseSpec)
import SumSpec.Syntax
import System.Directory (canonicalizePath)
import System.FilePath (normalise, takeDirectory, (</>))
import System.IO.Error (isDoesNotExistError)

-- | A spec read from a file: its source, the spec or its parse error, and
-- its imports.
data Loaded = Loaded
  { loadedSource :: Text
  , loadedSpec :: Either ParseError Spec
  , loadedImports :: [Imported]
  }

-- | Reads and parses a spec, then loads its imports. The file itself must
-- be readable (it throws otherwise, as reading a file does).
loadSpec :: FilePath -> IO Loaded
loadSpec file = do
  source <- T.readFile file
  case parseSpec file source of
    Left err -> pure (Loaded source (Left err) [])
    Right spec -> Loaded source (Right spec) <$> loadImports file spec

-- | Loads the imports of a spec read from this file, whose text may not be
-- saved yet (the language server's open document).
loadImports :: FilePath -> Spec -> IO [Imported]
loadImports file spec = do
  self <- canonical file
  importsOf [(self, file)] file spec

-- | The imports of a spec, with the files on the way to it (innermost
-- first, canonical and as shown), to find a cycle.
importsOf :: [(FilePath, FilePath)] -> FilePath -> Spec -> IO [Imported]
importsOf stack importer spec = traverse load (specImports spec)
  where
    load decl = Imported decl <$> result decl
    result decl = do
      let shown = normalise (takeDirectory importer </> T.unpack (importPath decl))
      canon <- canonical shown
      case break ((== canon) . fst) stack of
        (inner, (_, start) : _) ->
          pure (ImportCycle (start : reverse (map snd inner) <> [shown]))
        (_, []) -> do
          read' <- try (T.readFile shown)
          case read' of
            Left err -> pure (ImportUnreadable shown (reason err))
            Right source -> case parseSpec shown source of
              Left _ -> pure (ImportUnparsable shown)
              Right base -> do
                subs <- importsOf ((canon, shown) : stack) shown base
                pure $ case [files | Imported _ (ImportCycle files) <- subs] of
                  -- A cycle further on is this import's cycle too.
                  files : _ -> ImportCycle files
                  [] ->
                    ImportLoaded
                      (Base (nameText (importName decl)) shown source base (importedBases subs))
                      (hasErrors (checkSpecWith subs shown source base))
                      ((canon, shown) : concat [files | Imported _ (ImportLoaded _ _ files) <- subs])
    reason :: IOException -> Text
    reason err
      | isDoesNotExistError err = "no such file"
      | otherwise = T.pack (show err)

-- | The bases of the imports that loaded, for 'SumSpec.Model.modelWith'.
importedBases :: [Imported] -> [Base]
importedBases imports = [b | Imported _ (ImportLoaded b _ _) <- imports]

-- | One path for each file, to tell whether two imports reach the same
-- one. A path that can't be resolved stands for itself.
canonical :: FilePath -> IO FilePath
canonical path = either (const (normalise path)) id <$> tryIO (canonicalizePath path)
  where
    tryIO :: IO a -> IO (Either IOException a)
    tryIO = try
