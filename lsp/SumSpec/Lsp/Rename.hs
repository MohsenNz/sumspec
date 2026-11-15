{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Rename: every occurrence of the name under the cursor, as text edits.
--
-- A name can be renamed where it is defined in this file. A name defined
-- in a base spec, a qualified name (@core.Todos@), a qualifier and a name
-- that doesn't resolve are refused: the edit would have to reach another
-- file or part of a name.
module SumSpec.Lsp.Rename
  ( prepareRenameAt
  , renameEdits
  ) where

import Data.Char (isAlphaNum, isAsciiLower, isAsciiUpper)
import Data.Text (Text)
import Data.Text qualified as T
import Language.LSP.Protocol.Types (Position, Range, TextEdit (..))
import SumSpec.Lsp.Index (Kind (..), Occurrence (..), occurrenceAt)
import SumSpec.Lsp.Position (nameRange)
import SumSpec.Syntax (Name (..))
import Text.Megaparsec (SourcePos (..))

-- | The occurrence under the cursor, when it can be renamed.
renamable :: Text -> FilePath -> Position -> [Occurrence] -> Either Text Occurrence
renamable source file cursor occs = case occurrenceAt source cursor occs of
  Nothing -> Left "There is no name here."
  Just o
    | occKind o == KQualifier -> Left "A qualifier can't be renamed."
    | T.any (== '.') (nameText (occName o)) -> Left "A qualified name can't be renamed."
    | Just t <- occTarget o ->
        if sourceName (namePos t) == file
          then Right o
          else Left "This name is defined in another file."
    | otherwise -> Left "This name isn't defined."

-- | The range and the current text of the name under the cursor, when it
-- can be renamed.
prepareRenameAt
  :: Text -> FilePath -> Position -> [Occurrence] -> Maybe (Range, Text)
prepareRenameAt source file cursor occs =
  case renamable source file cursor occs of
    Right o -> Just (nameRange source (occName o), nameText (occName o))
    Left _ -> Nothing

-- | The edits that rename the name under the cursor, or why it can't be.
renameEdits
  :: Text -> FilePath -> Position -> Text -> [Occurrence] -> Either Text [TextEdit]
renameEdits source file cursor requested occs = do
  o <- renamable source file cursor occs
  let
    kind = occKind o
    new = if kind == KAnnotation then T.dropWhile (== '@') requested else requested
  validate kind new
  target <- maybe (Left "This name isn't defined.") Right (occTarget o)
  let clash =
        [ ()
        | d <- occs
        , occDefinition d
        , occKind d `sameNamespace` kind
        , nameText (occName d) == new
        , occTarget d /= Just target
        ]
  if null clash
    then
      Right
        [ TextEdit
            (nameRange source (occName x))
            (if kind == KAnnotation then "@" <> new else new)
        | x <- occs
        , occTarget x == Just target
        ]
    else Left ("The name " <> new <> " is already defined.")

-- | The name has the shape of the kind: types, variants, constants and
-- named patterns start with a capital, the others with a small letter.
validate :: Kind -> Text -> Either Text ()
validate kind new = case T.uncons new of
  Nothing -> Left "The name is empty."
  Just (c, cs)
    | not (first c) -> Left ("The name must start with " <> expected <> " letter.")
    | not (T.all isIdent cs) -> Left "The name has a character a name can't have."
    | otherwise -> Right ()
  where
    capital = kind `elem` [KType, KVariant, KConst, KPattern]
    first = if capital then isAsciiUpper else isAsciiLower
    expected = if capital then "a capital" else "a small"
    isIdent c = (isAlphaNum c && fromEnum c < 128) || c == '_' || c == '\''

-- | Whether two kinds of name must differ from each other. Types,
-- constants and named patterns share a namespace. Variants (one per sum)
-- and values (one per transition) aren't checked here: the checker
-- reports a clash after the edit.
sameNamespace :: Kind -> Kind -> Bool
sameNamespace a b = case (space a, space b) of
  (Just x, Just y) -> x == y
  _ -> False
  where
    space :: Kind -> Maybe Int
    space = \case
      KType -> Just 0
      KConst -> Just 0
      KPattern -> Just 0
      KEvent -> Just 1
      KAnnotation -> Just 2
      _ -> Nothing
