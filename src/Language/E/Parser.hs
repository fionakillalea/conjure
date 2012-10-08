{-# LANGUAGE QuasiQuotes, ViewPatterns, OverloadedStrings #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}

module Language.E.Parser where

import Stuff.Generic
import Stuff.Pretty
import Stuff.CompT ()
import Language.E.Definition ( E, BuiltIn(..), Spec(..), RuleRefn, RuleRepr, RuleReprCase )
import Language.E.Data ( Fixity(..), operators, functionals )
import Language.E.Lexer ( Lexeme(..), lexemeFace, lexemeText, lexemeWidth, runLexer )
import Language.E.Pretty ()

import Control.Applicative ( Applicative, (<$>), (<$), (<*), (*>), (<*>), (<|>), some, many )
import Control.Monad ( (>=>), msum, void )
import Control.Monad.Error ( MonadError(..) )
import Control.Monad.Identity ( Identity(..) )

import Data.List ( minimumBy )
import Data.Maybe ( fromMaybe )
import Data.Ord ( comparing )

import Text.Parsec ( ParsecT, (<?>), tokenPrim, try, parse )
import Text.Parsec.Combinator ( between, optionMaybe, sepBy, sepBy1, sepEndBy1, eof )
import Text.Parsec.Pos ( incSourceLine, incSourceColumn, setSourceColumn )

import qualified Data.Text as T
import qualified Text.PrettyPrint as Pr

import Data.Generics.Uniplate.Data ( universe )


-- instance Pretty [Either Lexeme E] where
--     pretty xs = Pr.vcat $ flip map xs $ \ x -> case x of Left l -> Pr.text $ show l
--                                                          Right i -> pretty i

type Parser a = ParsecT [Lexeme] () Identity a

test_ParsePrint' ::
    ( Pretty primitive
    , Pretty (Generic primitive)
    ) => Parser (Generic primitive) -> T.Text -> IO ()
test_ParsePrint' p t = do
    let res = (runLexer >=> runParser p "") t
    case res of
        Left  e -> print e
        Right x -> do
            -- print x
            -- print $ prettyAsTree x
            print $ prettyAsPaths x
            print $ pretty x

test_ParsePrint :: T.Text -> IO ()
test_ParsePrint = test_ParsePrint' (inCompleteFile parseExpr)

runLexerAndParser :: (MonadError Pr.Doc m, Applicative m) => Parser a -> String -> T.Text -> m a
runLexerAndParser p s = runLexer >=> runParser p s

lexAndParseIO :: Parser a -> T.Text -> IO a
lexAndParseIO p t = do
    let res = (runLexer >=> runParser p "") t
    case res of
        Left  e -> error $ show e
        Right x -> return x

runParser :: (MonadError Pr.Doc m) => Parser a -> String -> [Lexeme] -> m a
runParser p s ls =
    -- error $ unlines $ map show ls
    case parse p s ls of
        Left  e -> throwError $ Pr.text $ show e
        Right x -> return x

-- consume white space after this yourself!
satisfyT :: (Lexeme -> Bool) -> Parser Lexeme
satisfyT predicate = tokenPrim showTok nextPos testTok
    where
      showTok     = show . lexemeFace
      testTok tok = if predicate tok then Just tok else Nothing
      nextPos pos L_Newline _ = incSourceLine (setSourceColumn pos 1) 1
      nextPos pos l         _ = incSourceColumn pos (lexemeWidth l)


parseSpec :: Parser Spec
parseSpec = do
    let
        pLanguage :: Parser (String,[Int])
        pLanguage = do
            l  <- lexeme L_language *> identifier
            is <- sepBy1 integer dot
            return (l, map fromInteger is)
    whiteSpace
    l  <- pLanguage
    xs <- many parseTopLevels
    eof
    return $ Spec l $ concat xs


parseMetaVariable :: Parser E
parseMetaVariable = do
    let isMeta LMetaVar {} = True
        isMeta _           = False
    LMetaVar iden <- satisfyT isMeta
    whiteSpace
    let idenStr = T.unpack iden
    return [xMake| metavar := [Prim (S idenStr)]
                 |]

parseExpr :: Parser E
parseExpr = do
    xs <- fixNegate <$> parseBeforeShunt
    -- error $ unlines $ map show xs
    if not $ checkAlternating xs
        then fail "Shunting Yard failed. How dare you."
        else shunt xs
    where
        fixNegate :: [Either Lexeme E] -> [Either Lexeme E]
        fixNegate ( Right a
                  : Right ([xMatch| [b] := unaryOp.negate |])
                  : cs
                  ) = fixNegate $ Right a : Left L_Minus : Right b : cs
        fixNegate (a:bs) = a : fixNegate bs
        fixNegate [] = []

        checkAlternating :: [Either a b] -> Bool
        checkAlternating [Right _] = True
        checkAlternating (Right _:Left _:rest) = checkAlternating rest
        checkAlternating _ = False

        shunt :: [Either Lexeme E] -> Parser E
        shunt xs = do
            result <- findPivotOp xs
            case result of
                Left x -> return x
                Right (before, op, after) -> do
                    b <- shunt before
                    a <- shunt after
                    -- return $ Tagged "binOp" [
                    --          Tagged (T.unpack $ lexemeText op)
                    --          [b,a]
                    --          ]
                    return [xMake| binOp.operator := [Prim (S $ T.unpack $ lexemeText op)]
                                 | binOp.left     := [b]
                                 | binOp.right    := [a]
                                 |]

        findPivotOp :: [Either Lexeme E] -> Parser (Either E ([Either Lexeme E], Lexeme, [Either Lexeme E]))
        findPivotOp [Right x] = return $ Left x
        findPivotOp xs = do
            let
                pivotPrec :: Int
                pivotFixity :: Fixity
                (pivotPrec,pivotFixity) = minimumBy (comparing fst)
                                [ (p, f) | Left l <- xs, (l',f,p) <- operators, l == l' ]

                chck op = case [ p | (l,_,p) <- operators, l == op ] of
                            [p] -> p == pivotPrec
                            _ -> False

                findFirst :: [Either Lexeme E] -> Parser ([Either Lexeme E], Lexeme, [Either Lexeme E])
                findFirst [] = fail "findPivotOp.findFirst"
                findFirst (Left i:is) | chck i = return ([], i, is)
                findFirst (i:is) = do
                    (before, op, after) <- findFirst is
                    return (i:before, op, after)

                findLast :: [Either Lexeme E] -> Parser ([Either Lexeme E], Lexeme, [Either Lexeme E])
                findLast is = do
                    (before, op, after) <- findFirst (reverse is)
                    return (reverse after, op, reverse before)

                findOnly :: [Either Lexeme E] -> Parser ([Either Lexeme E], Lexeme, [Either Lexeme E])
                findOnly is = do
                    f <- findFirst is
                    l <- findLast  is
                    if f == l
                        then return f
                        else fail "Ambiguous use of non-associative operator."

            let
                finder = case pivotFixity of
                            FLeft  -> findLast
                            FNone  -> findOnly
                            FRight -> findFirst
            Right <$> finder xs


parseAtomicExpr :: Parser E
parseAtomicExpr = do
    let
        prefixes = do
            fs <- some $ msum parsePrefixes
            return $ foldr1 (.) fs
        postfixes = do
            fs <- some $ msum parsePostfixes
            return $ foldr1 (.) (reverse fs)
        withPrefix  x = try x <|> do f <- prefixes; i <- x; return $ f i
        withPostfix x = do i <- x; mf <- optionMaybe postfixes; return $ case mf of Nothing -> i
                                                                                    Just f  -> f i
    withPrefix (withPostfix parseAtomicExpr_NoPrePost) <?> "expression"

parseAtomicExpr_NoPrePost :: Parser E
parseAtomicExpr_NoPrePost = msum $ map try
    $ parseHsTerm
    : parseOthers ++ 
    [ parseQuantifiedExpr parseExpr
    , parseMetaVariable
    , parseReference
    , parseValue
    , parseDomainAsExpr
    , parseWithLocals
    , parens parseExpr
    ]

parseHsTerm :: Parser E
parseHsTerm = do
    let isHsTerm L_HsTerm {} = True
        isHsTerm _ = False
    L_HsTerm t <- satisfyT isHsTerm
    whiteSpace
    let s = T.unpack t
    return [xMake| hsTerm := [Prim (S s)] |]

parseDomainAsExpr :: Parser E
parseDomainAsExpr = do
    d <- betweenTicks parseDomain
    return [xMake| domainInExpr := [d]
                 |]

parsePrefixes :: [Parser (E -> E)]
parsePrefixes = [parseUnaryMinus, parseUnaryNot]
    where
        parseUnaryMinus = do
            lexeme L_Minus
            return $ \ x -> [xMake| unaryOp.negate := [x] |]
        parseUnaryNot = do
            lexeme L_ExclamationMark
            return $ \ x -> [xMake| unaryOp.not := [x] |]

parsePostfixes :: [Parser (E -> E)]
parsePostfixes = [parseIndexed,parseFuncApply,parseReplace]
    where
        parseIndexed :: Parser (E -> E)
        parseIndexed = do
            let
                pIndexer = try pRList <|> parseExpr
                pRList   = do
                    i <- optionMaybe parseExpr
                    dot; dot
                    j <- optionMaybe parseExpr
                    return $ case (i,j) of
                        (Nothing, Nothing) -> [xMake| slicer := [] |]
                        (Just a , Nothing) -> [xMake| slicer.from := [a] |]
                        (Nothing, Just a ) -> [xMake| slicer.to   := [a] |]
                        (Just a , Just b ) -> [xMake| slicer.from := [a]
                                                    | slicer.to   := [b]
                                                    |]
            is <- brackets $ pIndexer `sepBy1` comma
            return $ \ x -> foldl (\ m' i -> [xMake| operator.index.left  := [m']
                                                   | operator.index.right := [i]
                                                   |] ) x is
        parseFuncApply :: Parser (E -> E)
        parseFuncApply = parens $ do
            xs <- parseExpr `sepBy1` comma
            return $ \ x -> [xMake| functionApply.actual := [x]
                                  | functionApply.args   := xs
                                  |]
        parseReplace :: Parser (E -> E)
        parseReplace = braces $ do
            let one = do
                    i <- parseExpr
                    lexeme L_LongArrow
                    j <- parseExpr
                    return (i,j)
            pairs <- one `sepBy1` comma
            return $ \ x -> foldl (\ m' (i,j) -> [xMake| operator.replace.arg1 := [m']
                                                       | operator.replace.old  := [i]
                                                       | operator.replace.new  := [j]
                                                       |] ) x pairs

parseOthers :: [Parser E]
parseOthers = [ parseFunctional l
              | l <- functionals
              ] ++ [parseTyped, parseTwoBars]
    where

        parseTwoBars :: Parser E
        parseTwoBars = do
            x <- between (lexeme L_Bar) (lexeme L_Bar) parseExpr
            return [xMake| operator.twoBars := [x] |]

        parseTyped :: Parser E
        parseTyped = parens $ do
            x <- parseExpr
            lexeme L_Colon
            y <- parseDomainAsExpr
            return [xMake| typed.left  := [x]
                         | typed.right := [y]
                         |]

        parseFunctional :: Lexeme -> Parser E
        parseFunctional l = do
            lexeme l
            xs <- parens $ parseExpr `sepBy1` comma
            return $ case (l,xs) of
                (L_image, y:ys) -> [xMake| functionApply.actual := [y]
                                         | functionApply.args   := ys
                                         |]
                _ -> Tagged "operator" [Tagged (lexemeText l) xs]

parseWithLocals :: Parser E
parseWithLocals = parens $ do
    i  <- parseExpr
    lexeme L_At
    js <- parseTopLevels
    return [xMake| withLocals.actual := [i]
                 | withLocals.locals := js
                 |]

parseReference :: Parser E
parseReference = do
    x <- identifier
    return [xMake| reference := [Prim (S x)]
                 |]

parseBeforeShunt :: Parser [Either Lexeme E]
parseBeforeShunt = some $ msum
    [ Right <$> try parseAtomicExpr
    , Left  <$> parseOp
    ]

parseOp :: Parser Lexeme
parseOp = msum [ do lexeme x; return x | (x,_,_) <- operators ]
    <?> "operator"

parseValue :: Parser E
parseValue = msum ( map try
    [ pBool, pInt
    , pMatrix, pMatrix', pTupleWith, pTupleWithout
    , pSet, pMSet
    , pFunction, pRelation, pPartition
    ] ) <?> "value"
    where
        pBool = do
            x <- Prim (B False) <$ lexeme L_false
                 <|>
                 Prim (B True)  <$ lexeme L_true
            return [xMake| value.literal := [x] |]

        pInt = do
            x <- Prim . I <$> integer
            return [xMake| value.literal := [x] |]

        pMatrix = do
            xs <- brackets (sepBy parseExpr comma)
            return [xMake| value.matrix.values := xs |]

        pMatrix' = brackets $ do
            xs <- sepBy parseExpr comma
            lexeme L_SemiColon
            r <- parseRange
            return [xMake| value.matrix.values     := xs
                         | value.matrix.indexrange := [r]
                         |]
        pTupleWith = do
            lexeme L_tuple
            xs <- parens $ sepBy parseExpr comma
            return [xMake| value.tuple.values := xs |]

        pTupleWithout = do
            xs <- parens $ countSepAtLeast 2 parseExpr comma
            return [xMake| value.tuple.values := xs |]

        pSet = do
            xs <- braces (sepBy parseExpr comma)
            return [xMake| value.set.values := xs |]

        pMSet = do
            lexeme L_mset
            xs <- parens (sepBy parseExpr comma)
            return [xMake| value.mset.values := xs |]

        pFunction = do
            lexeme L_function
            xs <- parens (sepBy inner comma)
            return [xMake| value.function.values := xs |]
            where
                inner = do
                    i <- parseExpr
                    lexeme L_LongArrow
                    j <- parseExpr
                    return [xMake| mapping := [i,j] |]

        pRelation = do
            lexeme L_relation
            xs <- parens (sepBy (try pTupleWith <|> pTupleWithout) comma)
            return [xMake| value.relation.values := xs |]

        pPartition = do
            lexeme L_partition
            xs <- parens (sepBy inner comma)
            return [xMake| value.partition := xs|]
            where
                inner = do
                    is <- braces (sepBy parseExpr comma)
                    return [xMake| part := is |]

parseRange :: Parser E
parseRange = msum [try pRange, pSingle]
    where
        pRange = do
            fr <- optionMaybe parseExpr
            dot; dot
            to <- optionMaybe parseExpr
            return $ case (fr,to) of
                (Nothing, Nothing) -> [xMake| range.open   := []    |]
                (Just x , Nothing) -> [xMake| range.from   := [x]   |]
                (Nothing, Just y ) -> [xMake| range.to     := [y]   |]
                (Just x , Just y ) -> [xMake| range.fromTo := [x,y] |]
        pSingle = do
            x <- parseExpr
            return [xMake| range.single := [x] |]

parseDomain :: Parser E
parseDomain = msum $ map try
    [ pBool, pInt, pEnum
    , pMatrix, pTupleWithout, pTupleWith
    , pSet, pMSet, pFunction, pFunction'
    , pRelation, pPartition
    , parseMetaVariable, pParens
    ]
    where
        pParens = parens parseDomain

        pBool = do
            lexeme L_bool
            return [xMake| domain.bool := [] |]

        pInt = do
            lexeme L_int
            mxs <- optionMaybe $ parens $ parseRange `sepBy` comma
            let xs = fromMaybe [] mxs
            return [xMake| domain.int.ranges := xs |]

        pEnum = do
            r <- parseReference
            xs <- optionMaybe $ parens $ parseRange `sepBy` comma
            case xs of
                Nothing -> return r
                Just ys -> return [xMake| domain.enum.name   := [r]
                                        | domain.enum.ranges := ys
                                        |]

        pMatrix = do
            lexeme L_matrix
            lexeme L_indexed
            lexeme L_by
            xs <- brackets (parseDomain `sepBy1` comma)
            lexeme L_of
            y  <- parseDomain
            return $
                foldr (\ i j -> [xMake| domain.matrix.index := [i]
                                      | domain.matrix.inner := [j]
                                      |]
                      ) y xs

        pTupleWith = do
            lexeme L_tuple
            xs <- parens $ parseDomain `sepBy` comma
            return [xMake| domain.tuple.inners := xs |]

        pTupleWithout = do
            xs <- parens $ countSepAtLeast 2 parseDomain comma
            return [xMake| domain.tuple.inners := xs |]

        pSet = do
            lexeme L_set
            x <- parseAttributes
            lexeme L_of
            y <- parseDomain
            return [xMake| domain.set.attributes := [x]
                         | domain.set.inner      := [y]
                         |]

        pMSet = do
            lexeme L_mset
            x <- parseAttributes
            lexeme L_of
            y <- parseDomain
            return [xMake| domain.mset.attributes := [x]
                         | domain.mset.inner      := [y]
                         |]

        pFunction = do
            lexeme L_function
            y <- parseDomain
            lexeme L_LongArrow
            z <- parseDomain
            return [xMake| domain.function.attributes.attrCollection := []
                         | domain.function.innerFrom  := [y]
                         | domain.function.innerTo    := [z]
                         |]

        pFunction' = do
            lexeme L_function
            x <- parseAttributes
            y <- parseDomain
            lexeme L_LongArrow
            z <- parseDomain
            return [xMake| domain.function.attributes := [x]
                         | domain.function.innerFrom  := [y]
                         | domain.function.innerTo    := [z]
                         |]

        pRelation = do
            lexeme L_relation
            x  <- parseAttributes
            lexeme L_of
            ys <- parens (parseDomain `sepBy` lexeme L_Times)
            return [xMake| domain.relation.attributes := [x]
                         | domain.relation.inners     := ys
                         |]

        pPartition = do
            lexeme L_partition
            x <- parseAttributes
            lexeme L_from
            y <- parseDomain
            return [xMake| domain.partition.attributes := [x]
                         | domain.partition.inner      := [y]
                         |]

parseAttributes :: Parser E
parseAttributes = do
    xs <- parens (parseAttribute `sepBy` comma) <|> return []
    return [xMake| attrCollection := map snd xs
                 |]
    -- return [xMake| attrCollection := map snd $ sortBy (comparing fst) xs
    --              |]
    where
        parseAttribute = msum [try parseNameValue, try parseName, parseDontCare]
        parseNameValue = do
            n <- parseReference
            v <- parseExpr
            return
                ( Just n
                , [xMake| attribute.nameValue.name  := [n]
                        | attribute.nameValue.value := [v]
                        |]
                )
        parseName = do
            n <- parseReference
            return
                ( Just n
                , [xMake| attribute.name := [n]
                        |]
                )
        parseDontCare = do
            dot; dot
            return
                ( Nothing
                , [xMake| attribute.dontCare := []
                        |]
                )

parseTopLevels :: Parser [E]
parseTopLevels = do
    let one = msum $ map try
                [ do
                    lexeme L_find
                    decls <- flip sepBy1 comma $ do
                        is <- parseReference `sepBy1` comma
                        colon
                        j  <- parseDomain
                        return [ [xMake| topLevel.declaration.find.name   := [i]
                                       | topLevel.declaration.find.domain := [j]
                                       |]
                               | i <- is ]
                    return $ concat decls
                    <?> "find statement"
                , do
                    lexeme L_given
                    decls <- flip sepBy1 comma $ do
                        is <- parseReference `sepBy1` comma
                        msum
                            [ do
                                colon
                                j <- parseDomain
                                return [ [xMake| topLevel.declaration.given.name   := [i]
                                               | topLevel.declaration.given.domain := [j]
                                               |]
                                       | i <- is ]
                            , do
                                lexeme L_new
                                lexeme L_type
                                lexeme L_enum
                                return [ [xMake| topLevel.declaration.given.name     := [i]
                                               | topLevel.declaration.given.typeEnum := []
                                               |]
                                       | i <- is ]
                            ]
                    return $ concat decls
                    <?> "given statement"
                , do
                    lexeme L_letting
                    decls <- flip sepBy1 comma $ do
                        is <- (try parseMetaVariable <|> parseReference) `sepBy1` comma
                        lexeme L_be
                        msum
                            [ do
                                lexeme L_new
                                lexeme L_type
                                msum
                                    [ do
                                        lexeme L_of
                                        lexeme $ LIdentifier "size"
                                        j <- parseExpr
                                        return [ [xMake| topLevel.letting.name := [i]
                                                       | topLevel.letting.typeUnnamed := [j]
                                                       |]
                                               | i <- is
                                               ]
                                    , do
                                        lexeme L_enum
                                        ys <- braces (parseReference `sepBy` comma) <|> return []
                                        return [ [xMake| topLevel.letting.name := [i]
                                                       | topLevel.letting.typeEnum.values := ys
                                                       |]
                                               | i <- is
                                               ]
                                    ]
                            , do
                                lexeme L_domain
                                j <- parseDomain
                                return [ [xMake| topLevel.letting.name   := [i]
                                               | topLevel.letting.domain := [j]
                                               |]
                                       | i <- is
                                       ]
                            , do
                                j <- parseExpr
                                return [ [xMake| topLevel.letting.name := [i]
                                               | topLevel.letting.expr := [j]
                                               |]
                                       | i <- is
                                       ]
                            , do
                                j <- parseLambda L_lambda
                                return [ [xMake| topLevel.letting.name   := [i]
                                               | topLevel.letting.lambda := [j]
                                               |]
                                       | i <- is
                                       ]
                            , do
                                j <- parseQuanDecl
                                return [ [xMake| topLevel.letting.name       := [i]
                                               | topLevel.letting.quantifier := [j]
                                               |]
                                       | i <- is
                                       ]
                            ]
                    return $ concat decls
                    <?> "letting statement"
                , do
                    lexeme L_dim
                    is <- parseReference `sepBy1` comma
                    colon
                    j  <- parseDomain
                    return [ [xMake| topLevel.declaration.dim.name   := [i]
                                   | topLevel.declaration.dim.domain := [j]
                                   |]
                           | i <- is
                           ]
                , do
                    let dimfind = do
                            lexeme L_find
                            i <- parseExpr
                            colon
                            j <- parseDomain
                            return [xMake| dimFind.name   := [i]
                                         | dimFind.domain := [j]
                                         |]
                    let nested = try dimfind <|> try (parseQuantifiedExpr nested) <|> parens nested
                    i <- nested
                    return [ [xMake| topLevel.declaration.nestedDimFind := [i]
                                   |]
                           ]
                , do
                    lexeme L_where
                    xs <- parseExpr `sepEndBy1` comma
                    return [ [xMake| topLevel.where := [x] |]
                           | x <- xs ]
                , do
                    lexeme L_such
                    lexeme L_that
                    xs <- parseExpr `sepEndBy1` comma
                    return [ [xMake| topLevel.suchThat := [x] |]
                           | x <- xs ]
                , do
                    lexeme L_minimising
                    x <- parseExpr
                    return [ [xMake| topLevel.objective.minimising := [x]
                                   |]
                           ]
                , do
                    lexeme L_maximising
                    x <- parseExpr
                    return [ [xMake| topLevel.objective.maximising := [x]
                                   |]
                           ]
                ]
    concat <$> some one

parseLambda :: Lexeme -> Parser E
parseLambda l = do
    lexeme l
    braces $ do
        param <- parseExpr
        lexeme L_LongArrow
        body  <- parseExpr
        return [xMake| lambda.param := [param]
                     | lambda.body  := [body]
                     |]

parseQuanDecl :: Parser E
parseQuanDecl = do
    lexeme L_quantifier
    braces $ do
        append   <- parseLambda $ LIdentifier "append"
        guard    <- parseLambda $ LIdentifier "guard"
        identity <- lexeme (LIdentifier "identity") *> parseExpr
        return [xMake| quantifierDecl.append   := [append]
                     | quantifierDecl.guard    := [guard]
                     | quantifierDecl.identity := [identity]
                     |]

parseQuantifiedExpr :: Parser E -> Parser E
parseQuantifiedExpr parseBody = do
        let pOp = msum [ [xMake| binOp.subset   := [] |] <$ lexeme L_subset
                       , [xMake| binOp.subsetEq := [] |] <$ lexeme L_subsetEq
                       , [xMake| binOp.in       := [] |] <$ lexeme L_in
                       ]
        qnName   <- parseMetaVariable <|> parseReference
        qnVars   <- parseStructural `sepBy1` comma
        qnDom    <- optionMaybe (colon *> parseDomain)
        qnExpr   <- optionMaybe ((,) <$> pOp <*> parseExpr)
        case (qnDom,qnExpr) of
            (Nothing, Nothing) -> fail "expecting something to quantify over"
            _ -> return ()
        qnGuard <- optionMaybe (comma *> parseExpr)
        qnBody  <- dot *> parseBody <?> "expecting body of a quantified expression"

        let emptyGuard = [ [xMake| emptyGuard := [] |] ]

        let
            singleStructurals = [ i | [xMatch| [i] := structural.single |] <- concatMap universe qnVars ]

            idenToSingleStructural i | i `elem` singleStructurals = [xMake| structural.single := [i] |]
            idenToSingleStructural (Tagged t xs) = Tagged t $ map idenToSingleStructural xs
            idenToSingleStructural i = i

        let
            fixedQuanDoms  = map idenToSingleStructural $ case qnDom  of Just a     -> [a]; _ -> []
            fixedQuanOps   = map idenToSingleStructural $ case qnExpr of Just (a,_) -> [a]; _ -> []
            fixedQuanExprs = map idenToSingleStructural $ case qnExpr of Just (_,a) -> [a]; _ -> []
            fixedGuards    = map idenToSingleStructural $ case qnGuard of Nothing -> emptyGuard ; Just g  -> [g]
            fixedBodys     = map idenToSingleStructural $ [qnBody]

        let
            f []     = error "The Impossible has happenned. in parseQuantifiedExpr.f"
            f [i]    = [xMake| quantified.quantifier   := [qnName]
                             | quantified.quanVar      := [i]
                             | quantified.quanOverDom  := fixedQuanDoms
                             | quantified.quanOverOp   := fixedQuanOps
                             | quantified.quanOverExpr := fixedQuanExprs
                             | quantified.guard        := fixedGuards
                             | quantified.body         := fixedBodys
                             |]
            f (i:is) = [xMake| quantified.quantifier   := [qnName]
                             | quantified.quanVar      := [i]
                             | quantified.quanOverDom  := fixedQuanDoms
                             | quantified.quanOverOp   := fixedQuanOps
                             | quantified.quanOverExpr := fixedQuanExprs
                             | quantified.guard        := emptyGuard
                             | quantified.body         := [f is]
                             |]
        return $ f qnVars

parseStructural :: Parser E
parseStructural = msum
    [ parseMetaVariable
    , do
        x <- parseReference
        return [xMake| structural.single := [x] |]
    , do
        xs <- parens $ parseStructural `sepBy1` comma
        return [xMake| structural.tuple := xs |]
    , do
        xs <- brackets $ parseStructural `sepBy1` comma
        return [xMake| structural.matrix := xs |]
    ]

parseRuleRefn :: String -> Parser [RuleRefn]
parseRuleRefn t = inCompleteFile $ do
    level     <- optionMaybe (brackets (fromInteger <$> integer))
    let
        one = do
            pattern   <- parseExpr
            templates <- some (lexeme L_SquigglyArrow >> parseExpr)
            locals    <- concat <$> many parseTopLevels
            return ( t
                   , level
                   , [xMake| rulerefn.pattern   := [pattern]
                           | rulerefn.templates := templates
                           | rulerefn.locals    := locals
                           |]
                   )
    some one

parseRuleReprCase :: Parser RuleReprCase
parseRuleReprCase = do
    lexeme L_CaseSeparator
    dom    <- parseDomain
    mcons  <- optionMaybe (lexeme L_SquigglyArrow >> parseExpr)
    locals <- concat <$> many parseTopLevels
    return (dom, mcons, locals)


parseRuleRepr :: String -> Parser RuleRepr
parseRuleRepr t = inCompleteFile $ do
    let arr i = lexeme L_SquigglyArrow >> i
    nmRepr <- arr identifier
    domOut <- arr parseDomain
    mcons  <- optionMaybe $ arr parseExpr
    locals <- concat <$> many parseTopLevels
    cases  <- some parseRuleReprCase
    return ( t
           , nmRepr
           , domOut
           , mcons
           , locals
           , cases
           )



-- type Stream = [Lexeme]
-- 
-- 
-- 
-- data Pos = Pos (Maybe FilePath) Integer Integer deriving Show
-- 
-- showPos :: Pos -> Doc
-- showPos (Pos  Nothing  line col) = "(at line" <+> P.integer line <+>
--                                     "column"  <+> P.integer col  <> ")"
-- showPos (Pos (Just fp) line col) = "(in file" <+> text fp        <+>
--                                     "at line" <+> P.integer line <+>
--                                     "column"  <+> P.integer col  <> ")"
-- 
-- 
-- 
-- newtype Parser a = Parser { runParser :: Pos -> Stream -> Either (Nested Doc) [(a, Pos, Stream)] }
-- 
-- fail :: Doc -> Parser a
-- fail msg = Parser $ \ pos _ -> Left (addToTop (showPos pos <+> msg) [])
-- 
-- failUnexpected :: Lexeme -> Doc -> Parser a
-- failUnexpected l msg = fail ("parsing error in" <+> lexemeFace l <> ", expecting" <+> msg <> ".")
-- 
-- instance Functor Parser where
--     fmap f parser = Parser $ \ pos stream ->
--         case runParser parser pos stream of
--             Left  msg     -> Left msg
--             Right results -> Right [ (f a, p, s) | (a, p, s) <- results ]
-- 
-- instance Applicative Parser where
--     pure  = return
--     (<*>) = ap
-- 
-- instance Alternative Parser where
--     empty = mzero
--     (<|>) = mplus
--     some p = (:) <$> p <*> many p
--     many p = some p <|> return []
-- 
-- instance Monad Parser where
--     fail msg = fail (text msg)
--     return a = Parser $ \ pos stream -> Right [(a, pos, stream)]
--     parser >>= f = Parser $ \ pos stream ->
--         case runParser parser pos stream of
--             Left  msg      -> Left msg
--             Right results' ->
--                 let
--                     applied = [ runParser (f a) p s | (a, p, s) <- results' ]
--                     msgs    = lefts  applied
--                     results = rights applied
--                 in  case results of
--                         [] -> Left $ Nested Nothing msgs
--                         _  -> Right (concat results)
-- 
-- instance MonadPlus Parser where
--     mzero = fail "mzero"
--     mplus a b = Parser $ \ pos stream ->
--         let
--             applied = [ runParser a pos stream, runParser b pos stream ]
--             msgs    = lefts  applied
--             results = rights applied
--         in  case results of
--                 [] -> Left $ Nested Nothing msgs
--                 _  -> Right (concat results)
-- 
-- 
-- 
-- infix 0 <?>
-- (<?>) :: Parser a -> Doc -> Parser a
-- -- parser <?> msg = trace (show msg) $ Parser $ \ pos stream ->
-- parser <?> msg = Parser $ \ pos stream ->
--     case runParser parser pos stream of
--         Left  err     -> Left $ addToTop (showPos pos <+> msg) [err]
--         Right results -> Right results
-- 
-- infix 0 <?>
-- (<?>) :: Parser a -> Doc -> Parser a
-- -- parser <?> msg = trace (show msg) $ Parser $ \ pos stream ->
-- parser <?> msg = Parser $ \ pos stream ->
--     case runParser parser pos stream of
--         Left  _       -> Left $ addToTop (showPos pos <+> msg) []
--         Right results -> Right results
-- 
-- infixl 3 <|>
-- (<|>) :: Parser a -> Parser a -> Parser a
-- a <|> b = Parser $ \ pos stream ->
--     case runParser a pos stream of
--         Left  err1    -> case runParser b pos stream of
--             Left  err2    -> Left $ Nested Nothing [err1, err2]
--             Right results -> Right results
--         Right results -> Right results
-- 
-- 
-- msum :: [Parser a] -> Parser a
-- msum = foldr1 (<|>)
-- 
-- next :: Parser Lexeme
-- next = satisfy (const True) <?> "next"
-- 
-- putBack :: Pos -> Lexeme -> Parser ()
-- putBack pos l = Parser $ \ _ stream -> Right [((),pos,(l:stream))]
-- 
-- satisfy :: (Lexeme -> Bool) -> Parser Lexeme
-- satisfy f = core <* (whiteSpace <|> eof)
--     where
--         core = Parser $ \ pos stream ->
--                     case stream of
--                         (x:xs) ->
--                             if f x
--                                 then Right [(x, advancePos x pos, xs)]
--                                 else
--                                     let msg = "parsing error in \"" <> lexemeFace x <> "\"."
--                                     in  Left $ addToTop msg []
--                         _ -> Left $ Nested Nothing []

inCompleteFile :: Parser a -> Parser a
inCompleteFile parser = do
    whiteSpace
    result <- parser
    eof
    return result

whiteSpace :: Parser ()
whiteSpace = void $ many $ satisfyT isWhiteSpace
    where
        isWhiteSpace :: Lexeme -> Bool
        isWhiteSpace L_Space     = True
        isWhiteSpace L_Tab       = True
        isWhiteSpace L_Newline   = True
        isWhiteSpace LComment {} = True
        isWhiteSpace _           = False

lexeme :: Lexeme -> Parser ()
lexeme l = void (satisfyT (l==) <* whiteSpace) <?> show (lexemeFace l)

lexeme' :: Lexeme -> Parser Lexeme
lexeme' l = l <$ lexeme l

identifier :: Parser String
identifier = T.unpack <$> identifierText

identifierText :: Parser T.Text
identifierText = do
    LIdentifier i <- satisfyT isIdentifier
    whiteSpace
    return i
    where isIdentifier LIdentifier {} = True
          isIdentifier _ = False

integer :: Parser Integer
integer = do
    LIntLiteral i <- satisfyT isInt
    whiteSpace
    return i
    where isInt LIntLiteral {} = True
          isInt _ = False

comma :: Parser ()
comma = lexeme L_Comma <?> "comma"

dot :: Parser ()
dot = lexeme L_Dot <?> "dot"

colon :: Parser ()
colon = lexeme L_Colon <?> "colon"

-- sepBy :: Parser a -> Parser () -> Parser [a]
-- -- sepBy a sep = many (a <* sep)
-- sepBy a sep = sepBy1 a sep <|> return []
-- 
-- sepBy1 :: Parser a -> Parser () -> Parser [a]
-- -- sepBy1 a sep = some (a <* sep)
-- sepBy1 a sep = do
--     x <- a
--     ( do sep; xs <- sepBy a sep; return (x:xs) ) <|> return [x]

-- parses a specified number of elements separated by the given separator
countSep :: Int -> Parser a -> Parser sep -> Parser [a]
countSep 1 p _   = (:[]) <$> p
countSep i p sep | i > 1 = (:) <$> (p <* sep) <*> countSep (i-1) p sep
countSep _ _ _   = return []

-- parses at least a given number of elements separated by the given separator
countSepAtLeast :: Int -> Parser a -> Parser sep -> Parser [a]
countSepAtLeast i p sep = (++) <$> countSep i p sep <*> many (sep *> p)


-- optionMaybe :: Parser a -> Parser (Maybe a)
-- optionMaybe p = Just <$> p <|> return Nothing
-- 
-- between :: Parser () -> Parser () -> Parser a -> Parser a
-- between before after inner = do
--     before
--     result <- inner
--     after
--     return result

betweenTicks :: Parser a -> Parser a
betweenTicks = between (lexeme L_BackTick) (lexeme L_BackTick)

parens :: Parser a -> Parser a
parens = between (lexeme L_OpenParen) (lexeme L_CloseParen)

braces :: Parser a -> Parser a
braces = between (lexeme L_OpenCurly) (lexeme L_CloseCurly)

brackets :: Parser a -> Parser a
brackets = between (lexeme L_OpenBracket) (lexeme L_CloseBracket)

-- chainL :: Parser (a -> a -> a) -> Parser a -> Parser a
-- chainL op p = do x <- p; rest x
--     where
--         rest x = ( do f <- op; y <- p; rest (f x y) )
--                <|> return x
-- 
-- chainR :: Parser (a -> a -> a) -> Parser a -> Parser a
-- chainR op p = scan
--     where
--         scan = do x <- p; rest x
-- 
--         rest x = ( do f <- op; y <- scan; return (f x y) )
--                <|> return x
-- 
-- chainN :: Parser (a -> a -> a) -> Parser a -> Parser a
-- chainN op p = do
--     a <- p
--     o <- op
--     b <- p
--     return (o a b)
-- 
-- test :: Parser [Lexeme]
-- test = do
--     let one = do
--             whiteSpace
--             lexeme' L_allDiff <|> lexeme' L_defined
--     is <- some one
--     eof
--     return is
--     -- whiteSpace
--     -- 
--     -- -- whiteSpace
--     -- lexeme L_allDiff <|> lexeme L_defined                               <?> "second"
--     -- whiteSpace
--     -- lexeme L_allDiff <|> lexeme L_defined                               <?> "third"
--     -- eof
-- 
-- next2 :: Parser [Lexeme]
-- next2 = do
--     i <- next
--     j <- next
--     return [i,j]
-- 
-- next3 :: Parser [Lexeme]
-- next3 = do
--     i <- next
--     j <- next
--     k <- next
--     return [i,j,k]
-- 
-- lexAndParse ::
--     ( Applicative m
--     , MonadError (Nested Doc) m
--     ) => Maybe FilePath -> Parser a -> T.Text -> m [a]
-- lexAndParse mfp parser string = do
--     lexemes <- runLexer string
--     results <- case runParser parser (Pos mfp 1 1) lexemes of
--                     Left err -> case mfp of
--                                     Just "<memory>" -> throwError $ Nested Nothing [ err
--                                                                                    , singletonNested $ textToDoc string
--                                                                                    ]
--                                     _ -> throwError err
--                     Right r  -> return r
--     return [ a | (a,_,_) <- results ]
-- 
-- parseEither :: Show a => Parser a -> String -> Either (Nested Doc) a
-- parseEither p s = case lexAndParse Nothing p (T.pack s) of
--     Left msg  -> Left msg
--     Right [a] -> Right a
--     Right as  -> Left $ addToTop "Unknown parsing error." (map (flip addToTop [] . text . show) as)
-- 
-- unsafeParse :: Show a => Parser a -> String -> a
-- unsafeParse p s = case parseEither p s of
--     Left  msg -> error $ show msg
--     Right a   -> a
-- 
-- lexAndParseIO :: Show a => Parser a -> T.Text -> IO [a]
-- lexAndParseIO parser string = case lexAndParse Nothing parser string of
--     Left msg -> do
--         putStrLn $ renderDoc $ nestedToDoc msg
--         return []
--     Right as -> do
--         -- mapM_ ppPrint as
--         return as
-- 
-- 
-- -- -- runParser :: MonadError (Nested Doc) m => Parser a -> Stream -> m [a]
-- -- -- runParser p ls = case P.papply' p () ls of
-- -- --     Left msg -> throwError msg
-- -- --     Right rs -> return [ r
-- -- --                        | (r,(),rest) <- rs
-- -- --                        -- , null rest
-- -- --                        ]
-- -- -- 
-- -- -- reserved :: Lexeme -> Parser ()
-- -- -- reserved l = do
-- -- --     i <- P.item
-- -- --     if i == l
-- -- --         then return ()
-- -- --         else failMsg $ "Expecting lexeme: " ++ show l
-- -- -- 
-- -- -- lexeme :: Parser Lexeme
-- -- -- lexeme = P.item
-- -- -- 
-- -- -- pTwo :: Parser (Lexeme, Lexeme)
-- -- -- pTwo = do
-- -- --     i <- lexeme
-- -- --     j <- lexeme
-- -- --     return (i,j)
-- -- -- 
-- -- -- pOne :: Parser (Lexeme, Lexeme)
-- -- -- pOne = do
-- -- --     i <- lexeme
-- -- --     return (i,i)
-- -- -- 
-- -- -- 
-- -- -- -- test :: Parser (Lexeme, Lexeme) -> T.Text -> IO ()
-- -- -- -- test p t = case lexAndParse p t of
-- -- -- --         Left msg -> error $ show msg
-- -- -- --         Right r  -> ppPrint r
