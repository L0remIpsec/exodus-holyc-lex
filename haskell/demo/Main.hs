-- boots Exodus in process and prints the tokens of a HolyC source.
--
--   exodus-lex-demo [t_root [hcrt_bin [source]]]
--
-- the paths default to T and HCRT.BIN in the current directory, so
-- the easy way to run it is from the root of an Exodus checkout.
module Main (main) where

import           System.Environment (getArgs)
import           System.Exit        (exitFailure)
import           System.IO          (hPutStrLn, stderr)

import qualified Exodus.Lex         as Lex

main :: IO ()
main = do
  args <- getArgs
  let root = arg 0 "T" args
      bin  = arg 1 "HCRT.BIN" args
      src  = arg 2 "I64 x = 42; F64 f = 3.14; \"a\\0b\";" args
  up <- Lex.boot root bin
  if not up
    then die' ("could not boot Exodus from " ++ show root ++ " and "
               ++ show bin ++ " (wrong directory?)")
    else do
      result <- Lex.lex src
      case result of
        Nothing  -> die' "HolyC's Lex rejected the source"
        Just tks -> mapM_ print tks
  where
    arg n dflt xs = case drop n xs of
      (x:_) -> x
      []    -> dflt
    die' msg = hPutStrLn stderr msg >> exitFailure
