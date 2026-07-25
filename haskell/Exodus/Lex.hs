-- |
-- Module      : Exodus.Lex
-- Description : Haskell bindings to Exodus's HolyC lexer bridge
--
-- drives the HolyC Lex routine through Exodus's ExodusLex C wrapper and
-- returns the full token stream as a list. the Exodus runtime has to
-- have loaded HCRT (BootstrapLoader has run and HolyC is live) before
-- you call any of these.
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
  , lex
  , withLex
    -- * raw bindings
  , ExodusLexResultPtr
  , c_ExodusLex
  , c_ExodusLexFree
  ) where

import           Prelude            hiding (lex)

import           Control.Exception  (bracket)
import           Data.Int           (Int64)
import           Foreign.C.String   (CString, peekCStringLen, withCString)
import           Foreign.C.Types    (CDouble (..), CSize (..))
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

-- ExodusLex re-enters the HolyC compiler, which can run for a while and
-- must not stall the GHC runtime, so it's a safe call. ExodusLexFree is
-- plain C frees and can stay unsafe.
foreign import ccall safe "ExodusLex"
  c_ExodusLex     :: CString -> IO ExodusLexResultPtr

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

-- | lex some HolyC source and return every token, minus the trailing
-- TK_EOF. returns @Nothing@ if the HolyC runtime isn't loaded.
lex :: String -> IO (Maybe [Token])
lex src = withLex src return

-- | bracketed variant. lexes @src@, hands the token list to the action
-- and frees the underlying C buffer once it's done.
withLex :: String -> ([Token] -> IO a) -> IO (Maybe a)
withLex src k =
  withCString src $ \csrc ->
    bracket (c_ExodusLex csrc) freeIfNotNull $ \resPtr ->
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
    peekStr
      | ctStr == nullPtr = pure ""
      | otherwise        = peekCStringLen (ctStr, fromIntegral ctStrLen)
