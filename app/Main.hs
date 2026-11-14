module Main (main) where

import Control.Monad (when)
import Data.Text.IO qualified as T
import SumSpec
  ( Loaded (..)
  , checkSpecWith
  , hasErrors
  , loadSpec
  , parseSpec
  , renderCheckErrors
  , renderParseError
  , renderSpec
  )
import SumSpec.Lsp (runLanguageServer)
import System.Environment (getArgs)
import System.Exit (ExitCode (..), exitFailure, exitWith)
import System.IO (hPutStr, hPutStrLn, stderr)

main :: IO ()
main =
  getArgs >>= \case
    ["parse", file] -> do
      source <- T.readFile file
      case parseSpec file source of
        Left err -> hPutStr stderr (renderParseError err) >> exitFailure
        Right spec -> T.putStr (renderSpec spec)
    ["check", file] -> do
      Loaded source parsed imports <- loadSpec file
      case parsed of
        Left err -> hPutStr stderr (renderParseError err) >> exitFailure
        Right spec -> do
          let problems = checkSpecWith imports file source spec
          hPutStr stderr (renderCheckErrors source problems)
          when (hasErrors problems) exitFailure
    ["lsp"] -> do
      code <- runLanguageServer
      exitWith (if code == 0 then ExitSuccess else ExitFailure code)
    _ -> do
      hPutStrLn stderr "usage: sumspec (parse | check) FILE\n       sumspec lsp"
      exitFailure
