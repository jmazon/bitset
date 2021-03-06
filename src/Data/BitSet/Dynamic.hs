{-# LANGUAGE CPP #-}
{-# LANGUAGE MagicHash #-}
{-# LANGUAGE UnboxedTuples #-}
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}

-----------------------------------------------------------------------------
-- |
-- Module      :  Data.BitSet.Dynamic
-- Copyright   :  (c) Sergei Lebedev, Aleksey Kladov, Fedor Gogolev 2013
--                Based on Data.BitSet (c) Denis Bueno 2008-2009
-- License     :  MIT
-- Maintainer  :  superbobry@gmail.com
-- Stability   :  experimental
-- Portability :  GHC
--
-- A space-efficient implementation of set data structure for enumerated
-- data types.
--
-- /Note/: Read below the synopsis for important notes on the use of
-- this module.
--
-- This module is intended to be imported @qualified@, to avoid name
-- clashes with "Prelude" functions, e.g.
--
-- > import Data.BitSet.Dynamic (BitSet)
-- > import qualified Data.BitSet.Dynamic as BS
--
-- The implementation uses 'Integer' as underlying container, thus it
-- grows automatically when more elements are inserted into the bit set.

module Data.BitSet.Dynamic
    (
    -- * Bit set type
      FasterInteger
    , BitSet

    -- * Operators
    , (\\)

    -- * Construction
    , empty
    , singleton
    , insert
    , delete

    -- * Query
    , null
    , size
    , member
    , notMember
    , isSubsetOf
    , isProperSubsetOf

    -- * Combine
    , union
    , difference
    , intersection

    -- * Transformations
    , map

    -- * Folds
    , foldl'
    , foldr

    -- * Filter
    , filter

    -- * Lists
    , toList
    , fromList
    ) where

import Prelude hiding (null, map, filter, foldr)

import Data.Bits (Bits(..))
import GHC.Base (Int(..), divInt#, modInt#)
import GHC.Exts (popCnt#)
import GHC.Integer.GMP.Internals (Integer(..))
import GHC.Prim (State#, RealWorld, Int#, Word#, ByteArray#,
                 (+#), (==#), (>=#), (<#), negateInt#,
                 word2Int#, int2Word#, plusWord#, realWorld#,
                 newByteArray#, copyByteArray#, writeWordArray#,
                 indexWordArray#, unsafeFreezeByteArray#, sizeofByteArray#)
import GHC.Word (Word(..))

import Control.DeepSeq (NFData(..))

import Data.BitSet.Generic (GBitSet)
import qualified Data.BitSet.Generic as GS

-- | A wrapper around 'Integer' which provides faster bit-level operations.
newtype FasterInteger = FasterInteger { unFI :: Integer }
    deriving (Read, Show, Eq, Ord, Enum, Integral, Num, Real, NFData)

instance Bits FasterInteger where
    FasterInteger x .&. FasterInteger y = FasterInteger $ x .&. y
    {-# INLINE (.&.) #-}

    FasterInteger x .|. FasterInteger y = FasterInteger $ x .|. y
    {-# INLINE (.|.) #-}

    FasterInteger x `xor` FasterInteger y = FasterInteger $ x `xor` y
    {-# INLINE xor #-}

    complement = FasterInteger . complement . unFI
    {-# INLINE complement #-}

    shift (FasterInteger x) = FasterInteger . shift x
    {-# INLINE shift #-}

    rotate (FasterInteger x) = FasterInteger . rotate x
    {-# INLINE rotate #-}

    bit = FasterInteger . bit
    {-# INLINE bit #-}

    testBit (FasterInteger x) i = testBitInteger x i
    {-# SPECIALIZE INLINE [1] testBit :: FasterInteger -> Int -> Bool #-}

    setBit (FasterInteger x) = FasterInteger . setBit x
    {-# SPECIALIZE INLINE setBit :: FasterInteger -> Int -> FasterInteger #-}

    clearBit (FasterInteger x) = FasterInteger . clearBitInteger x
    {-# SPECIALIZE INLINE clearBit :: FasterInteger -> Int -> FasterInteger #-}

    popCount (FasterInteger x) = I# (word2Int# (popCountInteger x))
    {-# SPECIALIZE INLINE popCount :: FasterInteger -> Int #-}

    bitSize = bitSize . unFI
    {-# INLINE bitSize #-}

    isSigned = isSigned . unFI
    {-# INLINE isSigned #-}

type BitSet = GBitSet FasterInteger

-- | /O(1)/. Is the bit set empty?
null :: BitSet a -> Bool
null = GS.null
{-# INLINE null #-}

-- | /O(1)/. The number of elements in the bit set.
size :: BitSet a -> Int
size = GS.size
{-# INLINE size #-}

-- | /O(1)/. Ask whether the item is in the bit set.
member :: Enum a => a -> BitSet a -> Bool
member = GS.member
{-# INLINE member #-}

-- | /O(1)/. Ask whether the item is in the bit set.
notMember :: Enum a => a -> BitSet a -> Bool
notMember = GS.notMember
{-# INLINE notMember #-}

-- | /O(max(n, m))/. Is this a subset? (@s1 isSubsetOf s2@) tells whether
-- @s1@ is a subset of @s2@.
isSubsetOf :: BitSet a -> BitSet a -> Bool
isSubsetOf = GS.isSubsetOf
{-# INLINE isSubsetOf #-}

-- | /O(max(n, m)/. Is this a proper subset? (ie. a subset but not equal).
isProperSubsetOf :: BitSet a -> BitSet a -> Bool
isProperSubsetOf = GS.isProperSubsetOf
{-# INLINE isProperSubsetOf #-}

-- | The empty bit set.
empty :: Enum a => BitSet a
empty = GS.empty
{-# INLINE empty #-}

-- | O(1). Create a singleton set.
singleton :: Enum a => a -> BitSet a
singleton = GS.singleton
{-# INLINE singleton #-}

-- | /O(1)/. Insert an item into the bit set.
insert :: a -> BitSet a -> BitSet a
insert = GS.insert
{-# INLINE insert #-}

-- | /O(1)/. Delete an item from the bit set.
delete :: a -> BitSet a -> BitSet a
delete = GS.delete
{-# INLINE delete #-}

-- | /O(max(m, n))/. The union of two bit sets.
union :: BitSet a -> BitSet a -> BitSet a
union = GS.union
{-# INLINE union #-}

-- | /O(1)/. Difference of two bit sets.
difference :: BitSet a -> BitSet a -> BitSet a
difference = GS.difference
{-# INLINE difference #-}

-- | /O(1)/. See `difference'.
(\\) :: BitSet a -> BitSet a -> BitSet a
(\\) = difference

-- | /O(1)/. The intersection of two bit sets.
intersection :: BitSet a -> BitSet a -> BitSet a
intersection = GS.intersection
{-# INLINE intersection #-}

-- | /O(n)/ Transform this bit set by applying a function to every value.
-- Resulting bit set may be smaller then the original.
map :: (Enum a, Enum b) => (a -> b) -> BitSet a -> BitSet b
map = GS.map
{-# INLINE map #-}

-- | /O(n)/ Reduce this bit set by applying a binary function to all
-- elements, using the given starting value.  Each application of the
-- operator is evaluated before before using the result in the next
-- application.  This function is strict in the starting value.
foldl' :: (b -> a -> b) -> b -> BitSet a -> b
foldl' = GS.foldl'
{-# INLINE foldl' #-}

-- | /O(n)/ Reduce this bit set by applying a binary function to all
-- elements, using the given starting value.
foldr :: (a -> b -> b) -> b -> BitSet a -> b
foldr = GS.foldr
{-# INLINE foldr #-}

-- | /O(n)/ Filter this bit set by retaining only elements satisfying a
-- predicate.
filter :: Enum a => (a -> Bool) -> BitSet a -> BitSet a
filter = GS.filter
{-# INLINE filter #-}

-- | /O(n)/. Convert the bit set set to a list of elements.
toList :: BitSet a -> [a]
toList = GS.toList
{-# INLINE toList #-}

-- | /O(n)/. Make a bit set from a list of elements.
fromList :: Enum a => [a] -> BitSet a
fromList = GS.fromList
{-# INLINE fromList #-}

popCountInteger :: Integer -> Word#
popCountInteger (S# i#)    = popCnt# (int2Word# i#)
popCountInteger (J# s# d#) = go 0# (int2Word# 0#) where
  go i acc =
      if i ==# s#
      then acc
      else go (i +# 1#) $ acc `plusWord#` popCnt# (indexWordArray# d# i)
{-# INLINE popCountInteger #-}

#include "MachDeps.h"
#ifndef WORD_SIZE_IN_BITS
#error WORD_SIZE_IN_BITS not defined!
#endif

divModInt# :: Int# -> Int# -> (# Int#, Int# #)
divModInt# x y = (# d, m #) where
  !d = x `divInt#` y
  !m = x `modInt#` y
{-# INLINE divModInt# #-}

abs# :: Int# -> Int#
abs# x = if x <# 0# then negateInt# x else x
{-# INLINE abs# #-}

testBitInteger :: Integer -> Int -> Bool
testBitInteger (S# i#) b = I# i# `testBit` b
testBitInteger (J# s# d#) (I# b#) =
    if b# <# 0# || block# >=# abs# s#
    then False
    else W# (indexWordArray# d# block#) `testBit` I# offset#
  where
    (# !block#, !offset# #) = b# `divModInt#` WORD_SIZE_IN_BITS#
{-# NOINLINE testBitInteger #-}

clearBitInteger :: Integer -> Int -> Integer
clearBitInteger (S# i#) b = S# i# `clearBit` b
clearBitInteger i@(J# s# d0#) (I# b#) =
    if b# <# 0# || block# >=# abs# s#
    then i
    else J# s# (go realWorld#)
  where
    (# !block#, !offset# #) = b# `divModInt#` WORD_SIZE_IN_BITS#

    go :: State# RealWorld -> ByteArray#
    go state0 =
        let !n = sizeofByteArray# d0#
            (# state1, !d1 #) = newByteArray# n state0
            state2 = copyByteArray# d0# 0# d1 0# n state1
            !(W# chunk) = W# (indexWordArray# d0# block#) `clearBit` I# offset#
            state3 = writeWordArray# d1 block# chunk state2
            (# _state4, d2 #) = unsafeFreezeByteArray# d1 state3
        in d2
{-# NOINLINE clearBitInteger #-}