{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE Rank2Types           #-}
{-# LANGUAGE ScopedTypeVariables  #-}
{-# LANGUAGE OverloadedStrings    #-}

-----------------------------------------------------------------------------
-- |
-- Module      :  Data.SBV.RegExp
-- Copyright   :  (c) Levent Erkok
-- License     :  BSD3
-- Maintainer  :  erkokl@gmail.com
-- Stability   :  experimental
--
-- A collection of regular-expression related utilities. The recommended
-- workflow is to import this module qualified as the names of the functions
-- are specificly chosen to be common identifiers. Also, it is recommended
-- you use the @OverloadedStrings@ extension to allow literal strings to be
-- used as symbolic-strings and regular-expressions when working with
-- this module.
-----------------------------------------------------------------------------

module Data.SBV.RegExp (
        -- * Regular expressions
        RegExp(..)
        -- * Matching
        , RegExpMatchable(..)
        -- * Constructing regular expressions
        -- ** Literals
        , exactly
        -- ** A class of characters
        , oneOf
        -- ** Spaces
        , newline, whiteSpaceNoNewLine, whiteSpace
        -- ** Separators
        , tab, punctuation
        -- ** Letters
        , asciiLetter, asciiLower, asciiUpper
        -- ** Digits
        , digit, octDigit, hexDigit
        -- ** Numbers
        , decimal, octal, hexadecimal, floating
        -- ** Identifiers
        , identifier
        ) where

import Data.SBV.Core.Data
import Data.SBV.Core.Model () -- instances only

import Data.SBV.String
import qualified Data.Char as C

-- For testing only
import Data.SBV.Char

-- For doctest use only
--
-- $setup
-- >>> import Prelude hiding (length)
-- >>> import Data.SBV.Provers.Prover (prove, sat)
-- >>> import Data.SBV.Utils.Boolean  ((<=>), (==>), bAny, (&&&), bnot)
-- >>> import Data.SBV.Core.Model
-- >>> :set -XOverloadedStrings
-- >>> :set -XScopedTypeVariables

-- | Matchable class. Things we can match against a 'RegExp'.
-- TODO: Currently SBV does *not* optimize this call if @s@ is concrete, but
-- rather directly defers down to the solver. We might want to perform the
-- operation on the Haskell side for performance reasons, should this become
-- important.
--
-- For instance, you can generate valid-looking phone numbers like this:
--
-- >>> :set -XOverloadedStrings
-- >>> let dig09 = Range '0' '9'
-- >>> let dig19 = Range '1' '9'
-- >>> let pre   = dig19 * Loop 2 2 dig09
-- >>> let post  = dig19 * Loop 3 3 dig09
-- >>> let phone = pre * "-" * post
-- >>> sat $ \s -> (s :: SString) `match` phone
-- Satisfiable. Model:
--   s0 = "222-2248" :: String
class RegExpMatchable a where
   -- | @`match` s r@ checks whether @s@ is in the language generated by @r@.
   match :: a -> RegExp -> SBool

-- | Matching a character simply means the singleton string matches the regex.
instance RegExpMatchable SChar where
   match = match . charToStr

-- | Matching symbolic strings.
instance RegExpMatchable SString where
   -- >>> prove $ \s -> match s "hello" <=> s .== "hello"
   -- Q.E.D.
   -- >>> prove $ \s -> match s (Loop 2 5 "xyz") ==> length s .>= 6
   -- Q.E.D.
   -- >>> prove $ \s -> match s (Loop 2 5 "xyz") ==> length s .<= 15
   -- Q.E.D.
   -- >>> prove $ \s -> match s (Loop 2 5 "xyz") ==> length s .>= 7
   -- Falsifiable. Counter-example:
   --   s0 = "xyzxyz" :: String
   match s r = lift1 (StrInRe r) opt s
     where -- TODO: Replace this with a function that concretely evaluates the string against the
           -- reg-exp, possible future work. But probably there isn't enough ROI.
           opt :: Maybe (String -> Bool)
           opt = Nothing

-- | A literal regular-expression, matching the given string exactly. Note that
-- with 'OverloadedStrings' extension, you can simply use a Haskell
-- string to mean the same thing, so this function is rarely needed.
--
-- >>> prove $ \(s :: SString) -> s `match` exactly "LITERAL" <=> s .== "LITERAL"
-- Q.E.D.
exactly :: String -> RegExp
exactly = Literal

-- | Helper to define a character class.
--
-- >>> prove $ \(c :: SChar) -> c `match` oneOf "ABCD" <=> bAny (c .==) (map literal "ABCD")
-- Q.E.D.
oneOf :: String -> RegExp
oneOf xs = Union [exactly [x] | x <- xs]

-- | Recognize a newline. Also includes carriage-return and form-feed.
--
-- >>> prove $ \c -> c `match` newline ==> isSpace c
-- Q.E.D.
newline :: RegExp
newline = oneOf "\n\r\f"

-- | Recognize a tab.
--
-- >>> prove $ \c -> c `match` tab ==> c .== literal '\t'
-- Q.E.D.
tab :: RegExp
tab = oneOf "\t"

-- | Recognize white-space, but without a new line.
--
-- >>> prove $ \c -> c `match` whiteSpaceNoNewLine ==> c `match` whiteSpace &&& c ./= literal '\n'
-- Q.E.D.
whiteSpaceNoNewLine :: RegExp
whiteSpaceNoNewLine = tab + oneOf "\v\160 "

-- | Recognize white space.
--
-- >>> prove $ \c -> c `match` whiteSpace ==> isSpace c
-- Q.E.D.
whiteSpace :: RegExp
whiteSpace = newline + whiteSpaceNoNewLine

-- | Recognize a punctuation character. Anything that satisfies the predicate 'isPunctuation' will
-- be accepted.
--
-- >>> prove $ \c -> c `match` punctuation ==> isPunctuation c
-- Q.E.D.
punctuation :: RegExp
punctuation = oneOf $ filter C.isPunctuation $ map C.chr [0..255]

-- | Recognize an alphabet letter, i.e., @A@..@Z@, @a@..@z@.
asciiLetter :: RegExp
asciiLetter = asciiLower + asciiUpper

-- | Recognize an ASCII lower case letter
asciiLower :: RegExp
asciiLower = Range 'a' 'z'

-- | Recognize an upper case letter
asciiUpper :: RegExp
asciiUpper = Range 'A' 'Z'

-- | Recognize a digit. One of @0@..@9@.
--
-- >>> prove $ \c -> c `match` digit <=> let v = digitToInt c in 0 .<= v &&& v .< 10
-- Q.E.D.
digit :: RegExp
digit = Range '0' '9'

-- | Recognize an octal digit. One of @0@..@7@.
--
-- >>> prove $ \c -> c `match` octDigit <=> let v = digitToInt c in 0 .<= v &&& v .< 8
-- Q.E.D.
-- >>> prove $ \(c :: SChar) -> c `match` octDigit ==> c `match` digit
-- Q.E.D.
octDigit :: RegExp
octDigit = Range '0' '7'

-- | Recognize a hexadecimal digit. One of @0@..@9@, @a@..@f@, @A@..@F@.
--
-- >>> prove $ \c -> c `match` hexDigit <=> let v = digitToInt c in 0 .<= v &&& v .< 16
-- Q.E.D.
-- >>> prove $ \(c :: SChar) -> c `match` digit ==> c `match` hexDigit
-- Q.E.D.
hexDigit :: RegExp
hexDigit = digit + Range 'a' 'f' + Range 'A' 'F'

-- | Recognize a decimal number.
--
-- >>> prove $ \s -> (s::SString) `match` decimal ==> bnot (s `match` KStar asciiLetter)
-- Q.E.D.
decimal :: RegExp
decimal = KPlus digit

-- | Recognize an octal number. Must have a prefix of the form @0o@\/@0O@.
octal :: RegExp
octal = ("0o" + "0O") * KPlus octDigit

-- | Recognize a hexadecimal number. Must have a prefix of the form @0x@\/@0X@.
hexadecimal :: RegExp
hexadecimal = ("0x" + "0X") * KPlus hexDigit

-- | Recognize a floating point number. The exponent part is optional if a fraction
-- is present. The exponent may or may not have a sign.
floating :: RegExp
floating = withFraction + withoutFraction
  where withFraction    = decimal * "." * decimal * Opt expt
        withoutFraction = decimal * expt
        expt            = ("e" + "E") * Opt (oneOf "+-") * decimal

-- | For the purposes of this regular expression, an identifier consists of a letter
-- followed by zero or more letters, digits, underscores, and single quotes. The first
-- letter must be lowercase.
identifier :: RegExp
identifier = asciiLower * KStar (asciiLetter + digit + "_" + "'")

-- | Lift a unary operator over strings.
lift1 :: forall a b. (SymWord a, SymWord b) => StrOp -> Maybe (a -> b) -> SBV a -> SBV b
lift1 w mbOp a
  | Just cv <- concEval1 mbOp a
  = cv
  | True
  = SBV $ SVal k $ Right $ cache r
  where k = kindOf (undefined :: b)
        r st = do swa <- sbvToSW st a
                  newExpr st k (SBVApp (StrOp w) [swa])

-- | Concrete evaluation for unary ops
concEval1 :: (SymWord a, SymWord b) => Maybe (a -> b) -> SBV a -> Maybe (SBV b)
concEval1 mbOp a = literal <$> (mbOp <*> unliteral a)

-- | Quiet GHC about testing only imports
__unused :: a
__unused = undefined isSpace
