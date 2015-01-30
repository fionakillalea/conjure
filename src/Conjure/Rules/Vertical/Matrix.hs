{-# LANGUAGE QuasiQuotes #-}

module Conjure.Rules.Vertical.Matrix where

import Conjure.Prelude
import Conjure.Language.Definition
import Conjure.Language.Type
import Conjure.Language.Domain
import Conjure.Language.DomainOf
import Conjure.Language.Pretty
import Conjure.Language.TypeOf
import Conjure.Language.Lenses
import Conjure.Language.TH

import Conjure.Rules.Definition ( Rule(..), namedRule, matchFirst )

import Conjure.Representations ( downX1 )
import Conjure.Rules.Vertical.Tuple ( decomposeLexLt, decomposeLexLeq )


rule_Comprehension_Literal :: Rule
rule_Comprehension_Literal = "matrix-comprehension-literal" `namedRule` theRule where
    theRule (Comprehension body gensOrConds) = do
        (gofBefore, (pat, expr), gofAfter) <- matchFirst gensOrConds $ \ gof -> case gof of
            Generator (GenInExpr pat@Single{} expr) -> return (pat, expr)
            _ -> na "rule_Comprehension_Literal"
        (index, _elems) <- match matrixLiteral expr
        let upd val old = lambdaToFunction pat old val
        return
            ( "Vertical rule for matrix-comprehension"
            , \ fresh ->
                 let (iPat, i) = quantifiedVar (fresh `at` 0)
                     val = make opIndexing expr i
                 in  Comprehension (upd val body)
                         $  gofBefore
                         ++ [Generator (GenDomainNoRepr iPat index)]
                         ++ transformBi (upd val) gofAfter
            )
    theRule _ = na "rule_Comprehension_Literal"


rule_Comprehension_Literal_ContainsSet :: Rule
rule_Comprehension_Literal_ContainsSet = "matrix-comprehension-literal-containsSet" `namedRule` theRule where
    theRule (Comprehension body gensOrConds) = do
        (gofBefore, (pat, expr), gofAfter) <- matchFirst gensOrConds $ \ gof -> case gof of
            Generator (GenInExpr pat@Single{} expr) -> return (pat, expr)
            _ -> na "rule_Comprehension_Literal_ContainsSet"
        (matrix, indexer) <- match opIndexing expr
        (index, elems')   <- match matrixLiteral matrix
        elems             <- mapM (match setLiteral) elems'
        let insideOut = make setLiteral
                [ make opIndexing (make matrixLiteral index inMatrix) indexer
                | inMatrix <- transpose elems
                ]
        let upd val old = lambdaToFunction pat old val
        return
            ( "Vertical rule for matrix-comprehension"
            , \ fresh ->
                 let (iPat, i) = quantifiedVar (fresh `at` 0)
                 in  Comprehension (upd i body)
                         $  gofBefore
                         ++ [Generator (GenInExpr iPat insideOut)]
                         ++ transformBi (upd i) gofAfter
            )
    theRule _ = na "rule_Comprehension_Literal_ContainsSet"


rule_Comprehension_ToSet :: Rule
rule_Comprehension_ToSet = "matrix-toSet" `namedRule` theRule where
    theRule (Comprehension body gensOrConds) = do
        (gofBefore, (pat, expr), gofAfter) <- matchFirst gensOrConds $ \ gof -> case gof of
            Generator (GenInExpr pat@Single{} expr) -> return (pat, expr)
            _ -> na "rule_Comprehension_ToSet"
        matrix       <- match opToSet expr
        TypeMatrix{} <- typeOf matrix
        let upd val old = lambdaToFunction pat old val
        return
            ( "Vertical rule for comprehension over matrix-toSet"
            , \ fresh ->
                 let (iPat, i) = quantifiedVar (fresh `at` 0)
                     val  = make opIndexing i 1
                     over = make opHist matrix
                 in  Comprehension (upd val body)
                         $  gofBefore
                         ++ [Generator (GenInExpr iPat over)]
                         ++ transformBi (upd val) gofAfter
            )
    theRule _ = na "rule_Comprehension_ToSet"


-- [ i | ... , i <- [ j | ... j ... ], ... i ... ]
-- [ j | ... , ... j ..., ... j ... ]
rule_Comprehension_Nested :: Rule
rule_Comprehension_Nested = "matrix-comprehension-nested" `namedRule` theRule where
    theRule (Comprehension body gensOrConds) = do
        (gofBefore, (pat, innerBody, innerGof), gofAfter) <- matchFirst gensOrConds $ \ gof -> case gof of
            Generator (GenInExpr pat@Single{} (Comprehension innerBody innerGof)) -> return (pat, innerBody, innerGof)
            _ -> na "rule_Comprehension_Nested"
        let upd val old = lambdaToFunction pat old val
        return
            ( "Nested matrix comprehension"
            , const $ Comprehension (upd innerBody body)
                         $  gofBefore
                         ++ innerGof
                         ++ transformBi (upd innerBody) gofAfter
            )
    theRule _ = na "rule_Comprehension_Nested"


withAuxVar :: Name -> Domain () Expression -> (Expression -> Expression) -> Expression
withAuxVar nm dom f =
    WithLocals
        (Reference nm Nothing)
        [ Declaration (FindOrGiven LocalFind nm dom)
        , SuchThat [f (Reference nm Nothing)]
        ]


rule_Comprehension_ToSet2 :: Rule
rule_Comprehension_ToSet2 = "matrix-toSet2" `namedRule` theRule where
    theRule p = do
        let lu (Comprehension body gof) = return (body, gof)
            lu (Reference _ (Just (Alias ref))) = lu ref
            lu _ = fail "not a comprehension"
        inToSet     <- match opToSet p
        (body, gof) <- lu inToSet
        domBody     <- domainOf body
        return
            ( "Vertical rule for comprehension over matrix-hist"
            , \ fresh -> withAuxVar
                    (fresh `at` 0)
                    (DomainSet () def (forgetRepr "rule_Comprehension_ToSet2" domBody)) $ \ aux ->
                        make opAnd $ return $ Comprehension [essence| &body in &aux |] gof
            )


rule_Comprehension_Hist :: Rule
rule_Comprehension_Hist = "matrix-hist" `namedRule` theRule where
    theRule (Comprehension body gensOrConds) = do
        (gofBefore, (pat, expr), gofAfter) <- matchFirst gensOrConds $ \ gof -> case gof of
            Generator (GenInExpr pat@Single{} expr) -> return (pat, expr)
            _ -> na "rule_Comprehension_Hist"
        matrix               <- match opHist expr
        TypeMatrix{}         <- typeOf matrix
        DomainMatrix index _ <- domainOf matrix
        let upd val old = lambdaToFunction pat old val
        return
            ( "Vertical rule for comprehension over matrix-hist"
            , \ fresh ->
                 let (iPat, i) = quantifiedVar (fresh `at` 0)
                     (jPat, j) = quantifiedVar (fresh `at` 1)
                     value = [essence| &matrix[&i] |]
                     -- if this is the left-most occurrence of value
                     -- count all
                     -- otherwise, 0
                     count = [essence|
                         sum([ 1                            $ number of occurrences of this value in the matrix
                             | &jPat : &index
                             , &matrix[&i] = &matrix[&j]
                             ])
                     |]
                     val   = AbstractLiteral $ AbsLitTuple [value, count]
                     appearsBefore = [essence|
                         or([ &matrix[&j] = &matrix[&i]
                            | &jPat : &index
                            , &j < &i
                            ])
                    |]
                 in  Comprehension (upd val body)
                         $  gofBefore
                         ++ [ Generator (GenDomainNoRepr iPat index)
                            , Condition [essence| ! &appearsBefore |]
                            ]
                         ++ transformBi (upd val) gofAfter
            )
    theRule _ = na "rule_Comprehension_Hist"


rule_Matrix_Eq :: Rule
rule_Matrix_Eq = "matrix-eq" `namedRule` theRule where
    theRule p = do
        (x,y)                <- match opEq p
        TypeMatrix{}         <- typeOf x        -- TODO: check if x and y have the same arity
        TypeMatrix{}         <- typeOf y
        index <- case (domainOf x, domainOf y) of
            (Just (DomainMatrix index _), _) -> return index
            (_, Just (DomainMatrix index _)) -> return index
            (Just _, _) -> fail "rule_Matrix_Eq"
            (_, Just _) -> fail "rule_Matrix_Eq"
            _ -> fail "Equality constraint between two matrices, but domainOf doesn't work on either."
        return
            ( "Horizontal rule for matrix ="
            , \ fresh ->
                 let (iPat, i) = quantifiedVar (fresh `at` 0)
                 in  [essence| forAll &iPat : &index . &x[&i] = &y[&i] |]
            )


sliceEnoughTimes :: MonadFail m => Expression -> m Expression
sliceEnoughTimes m = do
    tym    <- typeOf m
    let nestingLevel (TypeMatrix _ a) = 1 + nestingLevel a
        nestingLevel _ = 0 :: Int
    let howMany = nestingLevel tym
    let unroll a 0 = a
        unroll a i = make opSlicing (unroll a (i-1)) Nothing Nothing
    let sliced = unroll m howMany
    let flatten = if howMany > 0 then make opFlatten else id
    return $ flatten sliced


rule_Matrix_Lt_Primitive :: Rule
rule_Matrix_Lt_Primitive = "matrix-lt-primitive" `namedRule` theRule where
    theRule p = do
        (x,y)           <- match opLt p
        tx@TypeMatrix{} <- typeOf x        -- TODO: check if x and y have the same arity
        ty@TypeMatrix{} <- typeOf y
        unless (isPrimitiveType tx) $ fail ("not a primitive type:" <+> pretty tx)
        unless (isPrimitiveType ty) $ fail ("not a primitive type:" <+> pretty ty)
        x' <- sliceEnoughTimes x
        y' <- sliceEnoughTimes y
        return
            ( "Horizontal rule for matrix <"
            , const [essence| &x' <lex &y' |]
            )


rule_Matrix_Lt_Decompose :: Rule
rule_Matrix_Lt_Decompose = "matrix-lt-tuple" `namedRule` theRule where
    theRule p = do
        (x,y) <- match opLt p
        tx@TypeMatrix{} <- typeOf x     -- TODO: check matrix index & tuple arity
        ty@TypeMatrix{} <- typeOf y
        when (isPrimitiveType tx) $ fail ("this is a primitive type:" <+> pretty tx)
        when (isPrimitiveType ty) $ fail ("this is a primitive type:" <+> pretty ty)
        xs <- downX1 x
        ys <- downX1 y
        return
            ( "Horizontal rule for matrix <, decomposing"
            , const $ decomposeLexLt p xs ys
            )


rule_Matrix_Leq_Primitive :: Rule
rule_Matrix_Leq_Primitive = "matrix-leq-primitive" `namedRule` theRule where
    theRule p = do
        (x,y)           <- match opLeq p
        tx@TypeMatrix{} <- typeOf x        -- TODO: check if x and y have the same arity
        ty@TypeMatrix{} <- typeOf y
        unless (isPrimitiveType tx) $ fail ("not a primitive type:" <+> pretty tx)
        unless (isPrimitiveType ty) $ fail ("not a primitive type:" <+> pretty ty)
        x' <- sliceEnoughTimes x
        y' <- sliceEnoughTimes y
        return
            ( "Horizontal rule for matrix <="
            , const [essence| &x' <=lex &y' |]
            )


rule_Matrix_Leq_Decompose :: Rule
rule_Matrix_Leq_Decompose = "matrix-leq-tuple" `namedRule` theRule where
    theRule p = do
        (x,y) <- match opLeq p
        tx@TypeMatrix{} <- typeOf x     -- TODO: check matrix index & tuple arity
        ty@TypeMatrix{} <- typeOf y
        when (isPrimitiveType tx) $ fail ("this is a primitive type:" <+> pretty tx)
        when (isPrimitiveType ty) $ fail ("this is a primitive type:" <+> pretty ty)
        xs <- downX1 x
        ys <- downX1 y
        return
            ( "Horizontal rule for matrix <=, decomposing"
            , const $ decomposeLexLeq p xs ys
            )