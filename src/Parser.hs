{-# LANGUAGE FlexibleContexts, TupleSections #-}

module Parser ( parseInput, parseProg ) where

import Data.List
import Data.Maybe
import Text.Parsec
import Text.Parsec.Language (haskell)
import Text.Parsec.Token    (stringLiteral)

import Eval

type Parsed a = Either String a
type Parser a = Parsec String () a


-- | Parse a complete program; ie. multiple rules (LHS,RHS) ignoring comments
parseProg :: String -> Parsed (Prog,Inputs)
parseProg = parse' (progP <* eof) "src"  where

  progP = (,) . catMaybes <$> lineP `sepEndBy` cNewline
                          <*> (inputsP <* eof <|> [] <$ eof)

  -- Parsing the program
  lineP = Just <$> ruleP <|> comment

  ruleP = (,) <$> (spaces *> lhsP) <*> (rSepP *> rhsP <* spaces')

  lhsP = multi' (identP' <* spaces') `sepBy` iSepP
  rhsP = multi  (identP  <* spaces') `sepBy` iSepP

  rSepP = string' "->"
  iSepP = string' "+"

  multi' p = do
    x <- multi p
    case x of
      (i,s) | "In_" `isPrefixOf` s || "Out_" `isPrefixOf` s
              -> fail $ "invalid atom: '" ++ s ++ "'"
            | otherwise -> pure (i,s)

  multi p = (,) <$> (numberP <|> pure 1) <*> (spaces' *> p)

  -- Parsing possible inputs separated by bang
  inputsP = char '!' *> inputP `sepEndBy` many1 space

-- | Parse a single command-line argument of the form IDENT:NUMBER
parseInput :: Integer -> String -> Parsed (String,Integer)
parseInput = parse' (inputP <* eof) . ("arg-"++) . show


parse' :: Parser a -> SourceName -> String -> Parsed a
parse' p s = first (pretty . show) . parse p s  where
  pretty = ('\n':) . (++"\n") . concatMap ("  "++) . lines
  first f (a,b) = (f a,b)


{- Some more general parsers -}

inputP :: Parser (String,Integer)
inputP =  (,) <$> identP' <*> (char ':' *> numberP)
      <|> ("_",) . pred <$> numberP

comment :: Monoid m => Parser m
comment = mempty <$ char '#' <* many (noneOf "\n")

cNewline :: Parser ()
cNewline = () <$ newline <|> (comment <* newline)

spaces' :: Parser ()
spaces' = () <$ many (oneOf "\v\t\f ")

string' :: String -> Parser String
string' s = string s <* spaces'

numberP :: Parser Integer
numberP = read <$> many1 digit

identP :: Parser Ident
identP =  In  <$> suffixP "In_" identP'
      <|> suffixP "Out_" (OutNum <$> identP' <|> OutStr <$> stringLiteral haskell)
      <|> Id  <$> identP'
  where suffixP s p = try (string s) *> p

identP' :: Parser String
identP' = (:) <$> nd <*> many (nd <|> digit)  where
  nd = letter <|> char '_'
