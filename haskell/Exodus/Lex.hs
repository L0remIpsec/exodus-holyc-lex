-- |
-- Module      : Exodus.Lex
-- Description : Haskell bindings to Exodus's HolyC lexer bridge
--
-- drives the HolyC Lex routine through Exodus's ExodusLex C wrapper and
-- returns the full token stream as a list. call 'boot' once to bring a
-- full Exodus runtime up inside the process, after that 'lex' and
-- 'withLex' hand sources to its HolyC server task and block until the
-- tokens come back.
--
-- source and payload strings cross the bridge as raw bytes, one 'Char'
-- per byte (Latin-1 style, code points 0 to 255, anything above is cut
-- down to its low byte on the way in). HolyC is not UTF-8,
-- KernelA.HH for one spells pi as a lone 0xE3 byte, so decoding through
-- the locale would mangle or drop anything outside ASCII.
--
-- this is the real HolyC Lex, preprocessor included: @#include@ reads
-- files and @#exe{}@ runs HolyC inside your process. don't lex source
-- you wouldn't be willing to compile.
--
-- link against libexodus_lex (built by the Exodus CMake project with
-- BUILD_EXODUS_LEX_SHARED=ON, which is the default) by way of
-- extra-libraries: exodus_lex in the cabal file.
{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE RecordWildCards          #-}

module Exodus.Lex
  ( -- * high level
    Token(..)
  , TokenKind(..)
  , boot
  , lex
  , withLex
    -- * raw bindings
  , ExodusLexResultPtr
  , c_ExodusLexBoot
  , c_ExodusLexRemote
  , c_ExodusLexFree
  ) where

import           Prelude            hiding (lex)

import           Control.Exception  (bracket)
import           Data.Int           (Int64)
import           Foreign.C.String   (CString, peekCAStringLen, withCAString,
                                     withCString)
import           Foreign.C.Types    (CDouble (..), CInt (..), CSize (..))
import           Foreign.Marshal.Array (peekArray)
import           Foreign.Ptr        (Ptr, nullPtr)
import           Foreign.Storable   (Storable (..))

------------------------------------------------------------------------
-- public Haskell side types

-- | a decoded HolyC token id. ids below 0x100 are single chars or minor
-- tokens, ids at or above 0x100 are TK_* enums (see KernelA.HH).
data TokenKind
  = TkEof
  | TkIdent !String
  | TkStr   !String
  | TkI64   !Int64
  | TkChar  !Int64
  | TkF64   !Double
  | TkOther !Int64        -- ^ any other token id (operators, keywords, ...)
  deriving (Eq, Show)

data Token = Token
  { tokenKind :: !TokenKind
  , tokenLine :: !Int64
  , tokenRaw  :: !Int64    -- ^ raw HolyC token id
  } deriving (Eq, Show)

------------------------------------------------------------------------
-- C struct mirrors

-- | mirrors @struct ExodusToken@ from src/exodus/lex_ffi.h.
data CExodusToken = CExodusToken
  { ctTok    :: !Int64
  , ctLine   :: !Int64
  , ctI64    :: !Int64
  , ctF64    :: !Double
  , ctStr    :: !CString
  , ctStrLen :: !Int64
  }

instance Storable CExodusToken where
  sizeOf    _ = 8 * 6
  alignment _ = 8
  peek p = CExodusToken
    <$> peekByteOff p 0
    <*> peekByteOff p 8
    <*> peekByteOff p 16
    <*> (realToFrac <$> (peekByteOff p 24 :: IO CDouble))
    <*> peekByteOff p 32
    <*> peekByteOff p 40
  poke p CExodusToken{..} = do
    pokeByteOff p 0  ctTok
    pokeByteOff p 8  ctLine
    pokeByteOff p 16 ctI64
    pokeByteOff p 24 (realToFrac ctF64 :: CDouble)
    pokeByteOff p 32 ctStr
    pokeByteOff p 40 ctStrLen

-- | opaque pointer to @struct ExodusLexResult@. layout is
--   { ExodusToken *tokens; size_t count; }
type ExodusLexResultPtr = Ptr ()

------------------------------------------------------------------------
-- raw FFI

-- boot blocks until HCRT is up and lexing re-enters the HolyC compiler,
-- neither may stall the GHC runtime, so they're safe calls.
-- ExodusLexFree is plain C frees and can stay unsafe.
foreign import ccall safe "ExodusLexBoot"
  c_ExodusLexBoot :: CString -> CString -> IO CInt

foreign import ccall safe "ExodusLexRemote"
  c_ExodusLexRemote :: CString -> IO ExodusLexResultPtr

foreign import ccall unsafe "ExodusLexFree"
  c_ExodusLexFree :: ExodusLexResultPtr -> IO ()

------------------------------------------------------------------------
-- high level API

-- HolyC token id constants
tkEof, tkIdent, tkStr, tkI64, tkCharConst, tkF64 :: Int64
tkEof       = 0x000
tkIdent     = 0x100
tkStr       = 0x101
tkI64       = 0x102
tkCharConst = 0x103
tkF64       = 0x104

-- | boot the in-process Exodus runtime. @boot root bin@ mounts @root@
-- as T:/ and loads the HolyC image @bin@, both resolved against the
-- current working directory. True means the runtime is up; calling it
-- again after that is harmless and stays True. False comes back
-- straight away when either path is missing, and a failed boot can't
-- be retried in the same process. there is no shutdown, the runtime
-- lives until the process exits.
boot :: FilePath -> FilePath -> IO Bool
boot root bin =
  withCString root $ \croot ->
    withCString bin $ \cbin ->
      (== 0) <$> c_ExodusLexBoot croot cbin

-- | lex some HolyC source and return every token, minus the trailing
-- TK_EOF. returns @Nothing@ if 'boot' hasn't succeeded yet or if the
-- HolyC lexer rejected the source (an over long char constant, a
-- throw out of an @#exe{}@ block). safe to call from several Haskell
-- threads, requests queue up on the one HolyC server task.
lex :: String -> IO (Maybe [Token])
lex src = withLex src return

-- | bracketed variant. lexes @src@, hands the token list to the action
-- and frees the underlying C buffer once it's done.
withLex :: String -> ([Token] -> IO a) -> IO (Maybe a)
withLex src k =
  withCAString src $ \csrc ->
    bracket (c_ExodusLexRemote csrc) freeIfNotNull $ \resPtr ->
      if resPtr == nullPtr
        then return Nothing
        else do
          tokens <- readResult resPtr
          Just <$> k tokens
  where
    freeIfNotNull p
      | p == nullPtr = return ()
      | otherwise    = c_ExodusLexFree p

readResult :: ExodusLexResultPtr -> IO [Token]
readResult p = do
  tokensPtr <- peekByteOff p 0 :: IO (Ptr CExodusToken)
  CSize n   <- peekByteOff p 8 :: IO CSize
  raws      <- peekArray (fromIntegral n) tokensPtr
  -- drop the trailing TK_EOF if it's there
  let raws' = case reverse raws of
        (e:_) | ctTok e == tkEof -> take (length raws - 1) raws
        _                        -> raws
  mapM decode raws'

decode :: CExodusToken -> IO Token
decode CExodusToken{..} = do
  kind <- case ctTok of
    t | t == tkEof       -> pure TkEof
      | t == tkI64       -> pure (TkI64  ctI64)
      | t == tkCharConst -> pure (TkChar ctI64)
      | t == tkF64       -> pure (TkF64  ctF64)
      | t == tkIdent     -> TkIdent <$> peekStr
      | t == tkStr       -> TkStr   <$> peekStr
      | otherwise        -> pure (TkOther t)
  pure Token { tokenKind = kind, tokenLine = ctLine, tokenRaw = ctTok }
  where
    -- read exactly str_len bytes; TK_STR payloads may contain embedded
    -- NULs (\0 and \xNN escapes) that a plain peekCString would drop.
    -- byte for byte, no locale decoding (see the module header).
    peekStr
      | ctStr == nullPtr = pure ""
      | otherwise        = peekCAStringLen (ctStr, fromIntegral ctStrLen)
