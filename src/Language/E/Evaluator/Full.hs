{-# LANGUAGE QuasiQuotes, ViewPatterns, OverloadedStrings #-}

module Language.E.Evaluator.Full where

import Language.E.Imports
import Language.E.Definition
import Language.E.Helpers
import Language.E.CompE
import Language.E.DomainOf
import Language.E.MatchBind
import Language.E.TH
import Language.E.TypeOf
import Language.E.Pretty
import {-# SOURCE #-} Language.E.Evaluator.ToInt
import                Language.E.Evaluator.DataAboutQuantifiers


fullEvaluator :: MonadConjure m => E -> m (Maybe (E,[Binder]))
fullEvaluator [xMatch| [Prim (S "+")] := binOp.operator
                     | [Prim (I a)  ] := binOp.left .value.literal
                     | [Prim (I b)  ] := binOp.right.value.literal
                     |] = returnInt $ a + b
fullEvaluator [xMatch| [Prim (S "-")] := binOp.operator
                     | [Prim (I a)  ] := binOp.left .value.literal
                     | [Prim (I b)  ] := binOp.right.value.literal
                     |] = returnInt $ a - b
fullEvaluator [xMatch| [Prim (S "*")] := binOp.operator
                     | [Prim (I a)  ] := binOp.left .value.literal
                     | [Prim (I b)  ] := binOp.right.value.literal
                     |] = returnInt $ a * b
fullEvaluator [xMatch| [Prim (S "/")] := binOp.operator
                     | [Prim (I a)  ] := binOp.left .value.literal
                     | [Prim (I b)  ] := binOp.right.value.literal
                     |] | b > 0 = returnInt $ a `div` b
fullEvaluator [xMatch| [Prim (S "%")] := binOp.operator
                     | [Prim (I a)  ] := binOp.left .value.literal
                     | [Prim (I b)  ] := binOp.right.value.literal
                     |] | b > 0 = returnInt $ a `mod` b
fullEvaluator [xMatch| [Prim (S "**")] := binOp.operator
                     | [Prim (I a)   ] := binOp.left .value.literal
                     | [Prim (I b)   ] := binOp.right.value.literal
                     |] | b > 0 = returnInt $ a ^ b

fullEvaluator [eMatch| !false |] = ret [eMake| true  |]
fullEvaluator [eMatch| !true  |] = ret [eMake| false |]

fullEvaluator [eMatch| toInt(false) |] = ret [eMake| 0 |]
fullEvaluator [eMatch| toInt(true)  |] = ret [eMake| 1 |]

fullEvaluator [eMatch| &a = &b |]
    | [xMatch| [Prim a'] := value.literal |] <- a
    , [xMatch| [Prim b'] := value.literal |] <- b
    = returnBool (a' == b')

fullEvaluator [eMatch| &a != &b |]
    | [xMatch| [Prim (I a')] := value.literal |] <- a
    , [xMatch| [Prim (I b')] := value.literal |] <- b
    = returnBool (a' /= b')

fullEvaluator [xMatch| [Prim (S "/\\")] := binOp.operator
                     | [ ] := binOp.left.emptyGuard
                     | [x] := binOp.right
                     |] = ret x

fullEvaluator [xMatch| [Prim (S "/\\")] := binOp.operator
                     | [x] := binOp.left
                     | [ ] := binOp.right.emptyGuard
                     |] = ret x

fullEvaluator [xMatch| [Prim (S "union")] := binOp.operator
                     | xs := binOp.left.value.set.values
                     | ys := binOp.left.value.set.values
                     |] = ret $ [xMake| value.set.values := nub (xs ++ ys) |]

fullEvaluator [xMatch| [Prim (S "union")] := binOp.operator
                     | xs := binOp.left.value.mset.values
                     | ys := binOp.left.value.mset.values
                     |] = ret $ [xMake| value.mset.values := xs ++ ys |]

fullEvaluator [xMatch| xs := domain.int.ranges.range.single.value.set.values |]
    = let ys = map (\ i -> [xMake| range.single := [i] |] ) xs
      in  ret [xMake| domain.int.ranges := ys |]

-- fullEvaluator p@[eMatch| &quan &i : int(&a..&b) , &guard . &body |]
    -- | [xMatch| [Prim (S quanStr)] := reference |] <- quan
    -- , [xMatch| [Prim (I a')] := value.literal |] <- a
    -- , [xMatch| [Prim (I b')] := value.literal |] <- b
    -- , a' == b'
    -- = do
    -- res1 <- guardOp quanStr [guard] body
    -- let res2 = [eMake| &res1 { &i --> &a } |]
    -- mres3 <- evalReplace res2
    -- case mres3 of
        -- Just (res3, _) -> do
            -- mkLog "fullEvaluator 1" $ pretty p
            -- mkLog "fullEvaluator 2" $ pretty res3
            -- return mres3
        -- Nothing -> do
            -- mkLog "fullEvaluator Nothing" $ pretty p
            -- return Nothing

fullEvaluator [xMatch| vs           := operator.index.left .value.matrix.values
                     | [Prim (I i)] := operator.index.right.value.literal
                     |] | i >= 1 && i <= genericLength vs
                        = ret (vs `genericIndex` (i-1))
fullEvaluator [xMatch| vs           := operator.index.left .value.tuple.values
                     | [Prim (I i)] := operator.index.right.value.literal
                     |] | i >= 1 && i <= genericLength vs
                        = ret (vs `genericIndex` (i-1))

fullEvaluator p@[eMatch| &quan &_ : int(&a..&b) , &_ . &_ |]
    | [xMatch| [Prim (S quanStr)] := reference |] <- quan
    , [xMatch| [Prim (I a')] := value.literal |] <- a
    , [xMatch| [Prim (I b')] := value.literal |] <- b
    , a' > b'
    = do
        mkLog "fullEvaluator empty range" $ pretty p
        res <- identityOp quanStr
        ret res

fullEvaluator [eMatch| sum &i : int(&a..&b) , &guard . &body |]
    | [xMatch| [Prim (I a')] := value.literal |] <- a
    , [xMatch| [Prim (I b')] := value.literal |] <- b
    , [xMake| emptyGuard := [] |] == guard
    = ret $ summation [ replace i j body
                      | j' <- [a'..b']
                      , let j = [xMake| value.literal := [Prim (I j')] |]
                      ]

fullEvaluator [eMatch| &_ &i : int(&a..&b) . &body |]
    | a == b
    = ret $ replace i a body

fullEvaluator _ = return Nothing


returnBool :: MonadConjure m => Bool -> m (Maybe (E,[Binder]))
returnBool i = ret [xMake| value.literal := [Prim (B i)] |]

returnBool' :: MonadConjure m => Bool -> [Binder] -> m (Maybe (E,[Binder]))
returnBool' i bs = return $ Just ([xMake| value.literal := [Prim (B i)] |], bs)

returnInt :: MonadConjure m => Integer -> m (Maybe (E,[Binder]))
returnInt i | i > 1000 = return Nothing
returnInt i = ret [xMake| value.literal := [Prim (I i)] |]

returnInt' :: MonadConjure m => Integer -> [Binder] -> m (Maybe (E,[Binder]))
returnInt' i bs = return $ Just ([xMake| value.literal := [Prim (I i)] |], bs)

ret :: MonadConjure m => E -> m (Maybe (E,[Binder]))
ret i = return $ Just (i, [])


evalHasType :: MonadConjure m => E -> m (Maybe (E,[Binder]))
evalHasType [eMatch| &s hasType &dom |] = do
    ts <- typeOf s
    td <- typeOf dom
    (flag, bs) <- patternMatch td ts
    modify $ \ st -> st { binders = bs ++ binders st }
    returnBool' flag bs
evalHasType _ = return Nothing

evalHasDomain :: MonadConjure m => E -> m (Maybe (E,[Binder]))
evalHasDomain [eMatch| &x hasDomain &y |] = do
    dx <- domainOf x
    dy <- domainOf y
    (flag, bs) <- patternMatch dy dx
    returnBool' flag bs
evalHasDomain _ = return Nothing

evalHasRepr :: MonadConjure m => E -> m (Maybe (E,[Binder]))
evalHasRepr [eMatch| &x hasRepr &y |] =
    case x of
        [eMatch| &m[&_] |] ->
            evalHasRepr [eMake| &m hasRepr &y |]
        [xMatch| [Prim (S iden)] := metavar   |] -> do
            a <- errMaybeT "hasRepr" lookupMetaVar iden
            evalHasRepr [eMake| &a hasRepr &y |]
        [xMatch| [Prim (S iden )] := reference |] ->
            case identifierSplit iden of
                (_,_,Just idenReprName) ->
                    case y of
                        [xMatch| [Prim (S reprName)] := reference |] ->
                            returnBool $ idenReprName == reprName
                        _ -> err ErrFatal $ "Not a representation:" <+> pretty y
                _ -> returnBool False
        _ -> returnBool False
evalHasRepr _ = return Nothing

evalDomSize :: MonadConjure m => E -> m (Maybe (E,[Binder]))
evalDomSize [eMatch| domSize(&i) |] = ret =<< domSize i
    where
        sumE []     = [eMake| 0 |]
        sumE [x]    = x
        sumE [x,y]  = [eMake| &x + &y |]
        sumE (x:xs) = let sumxs = sumE xs in [eMake| &x + &sumxs |]

        mulE []     = [eMake| 1 |]
        mulE [x]    = x
        mulE [x,y]  = [eMake| &x * &y |]
        mulE (x:xs) = let mulxs = mulE xs in [eMake| &x * &mulxs |]

        domSize [xMatch| [Prim (S s)] := reference |] = do
            x <- errMaybeT "domSize" lookupReference s
            domSize x
        domSize [xMatch| rs := domain.int.ranges |] = do
            xs <- mapM domSize rs
            return $ sumE xs
        domSize [xMatch| [fr,to] := range.fromTo |] =
            return [eMake| &to - &fr + 1 |]
        domSize [xMatch| [_] := range.single |] =
            return [eMake| 1 |]

        domSize [xMatch| rs := domain.tuple.inners |] = do
            xs <- mapM domSize rs
            return $ mulE xs

        domSize [xMatch| [t] := domain.set.inner |] = do
            x <- domSize t
            return [eMake| 2 ** &x |]

        domSize [dMatch| mset (size &s) of &inn |] = do
            innSize <- domSize inn
            return [eMake| &s * &innSize |]
        domSize [xMatch| [t] := domain.mset.inner |] = do
            x <- domSize t
            return [eMake| 2 ** &x |]

        domSize [xMatch| [a] := domain.function.innerFrom
                       | [b] := domain.function.innerTo
                       |] = do
            aSize <- domSize a
            bSize <- domSize b
            return [eMake| &aSize * &bSize |]

        domSize p =
            err ErrFatal $ "domSize:" <+> prettyAsPaths p

evalDomSize _ = return Nothing

evalIndices :: MonadConjure m => E -> m (Maybe (E,[Binder]))
evalIndices p@[xMatch| [a,b] := operator.indices |] = do
    bInt <- toInt b
    case bInt of
        Nothing         -> err ErrFatal $ "Second argument is not an integer:" <+> pretty p
        Just (bInt', _) -> indices a bInt'
    where
        -- indices (matrix) (integer)
        indices :: MonadConjure m => E -> Integer -> m (Maybe (E,[Binder]))
        indices [xMatch| [Prim (S iden)] := reference |] i = do
            res <- errMaybeT "indices" lookupReference iden
            indices res i
        indices [xMatch| [d] := topLevel.declaration.find .domain |] i = indices d i
        indices [xMatch| [d] := topLevel.declaration.given.domain |] i = indices d i
        indices [xMatch| [index] := domain.matrix.index |] 0 = ret index
        indices [xMatch| [inner] := domain.matrix.inner |] i = indices inner (i-1)
        indices [eMatch| &m[&_]                         |] i = indices m (i+1)
        indices [xMatch| [d] := quanVar.within.quantified.quanOverDom |] i = indices d i
        indices m i = do
            mkLog "missing:indices" $ vcat [ pretty m
                                           , prettyAsPaths m
                                           , pretty i
                                           ]
            return Nothing
evalIndices _ = return Nothing

evalReplace :: MonadConjure m => E -> m (Maybe (E,[Binder]))
evalReplace
    [xMatch| [a] := operator.replace.arg1
           | [b] := operator.replace.old
           | [c] := operator.replace.new
           |] =
    let
        helper  old  new now | old == now = new
        helper  old  new (Tagged t xs) = Tagged t $ map (helper old new) xs
        helper _old _new other = other
    in  ret $ helper b c a
evalReplace _ = return Nothing

tupleEq :: MonadConjure m => E -> m (Maybe (E,[Binder]))
-- tupleEq x | trace (show $ "tupleEq:" <+> pretty x) False = undefined
tupleEq [eMatch| &a = &b |] = do
    ta <- flip const (show $ "fromFullEVal" <+> pretty a) $ typeOf a
    tb <- flip const (show $ "fromFullEVal" <+> pretty b) $ typeOf b
    case (ta,tb) of
        ([xMatch| is := type.tuple.inners |], _) ->
            ret $ conjunct [ [eMake| &a[&i] = &b[&i] |]
                           | j <- [1..genericLength is]
                           , let i = [xMake| value.literal := [Prim (I j)] |]
                           ]
        (_, [xMatch| is := type.tuple.inners |]) ->
            ret $ conjunct [ [eMake| &a[&i] = &b[&i] |]
                           | j <- [1..genericLength is]
                           , let i = [xMake| value.literal := [Prim (I j)] |]
                           ]
        _ -> return Nothing
tupleEq [eMatch| &a != &b |] = do
    ta <- flip const (show $ "fromFullEVal" <+> pretty a) $ typeOf a
    tb <- flip const (show $ "fromFullEVal" <+> pretty b) $ typeOf b
    case (ta,tb) of
        ([xMatch| is := type.tuple.inners |], _) ->
            ret $ disjunct [ [eMake| &a[&i] != &b[&i] |]
                           | j <- [1..genericLength is]
                           , let i = [xMake| value.literal := [Prim (I j)] |]
                           ]
        (_, [xMatch| is := type.tuple.inners |]) ->
            ret $ disjunct [ [eMake| &a[&i] != &b[&i] |]
                           | j <- [1..genericLength is]
                           , let i = [xMake| value.literal := [Prim (I j)] |]
                           ]
        _ -> return Nothing
tupleEq [eMatch| &a[&i] |] = do
    miInt <- toInt i
    case miInt of
        Nothing        -> return Nothing
        Just (iInt, _) ->
            case a of
                [xMatch| vs := value.tuple.values |] -> ret $ vs `genericIndex` (iInt - 1)
                _ -> return Nothing
tupleEq _ = return Nothing


matrixEq :: MonadConjure m => E -> m (Maybe (E, [Binder]))
matrixEq [eMatch| &a = &b |] = do
    da <- (Just <$> domainOf a) `catchError` (\ _ -> return Nothing )
    db <- (Just <$> domainOf b) `catchError` (\ _ -> return Nothing )
    case (da,db) of
        (Just [xMatch| [ia] := domain.matrix.index |],_) -> do
            (quanVarStr, quanVar) <- freshQuanVar
            ret $ inForAll quanVarStr ia [eMake| &a[&quanVar] = &b[&quanVar] |]
        (_,Just [xMatch| [ia] := domain.matrix.index |]) -> do
            (quanVarStr, quanVar) <- freshQuanVar
            ret $ inForAll quanVarStr ia [eMake| &a[&quanVar] = &b[&quanVar] |]
        _ -> return Nothing
matrixEq [eMatch| &a != &b |] = do
    da <- (Just <$> domainOf a) `catchError` (\ _ -> return Nothing )
    db <- (Just <$> domainOf b) `catchError` (\ _ -> return Nothing )
    case (da,db) of
        (Just [xMatch| [ia] := domain.matrix.index |],_) -> do
            (quanVarStr, quanVar) <- freshQuanVar
            let res = inForAll quanVarStr ia [eMake| &a[&quanVar] = &b[&quanVar] |]
            ret [eMake| !&res |]
        (_,Just [xMatch| [ia] := domain.matrix.index |]) -> do
            (quanVarStr, quanVar) <- freshQuanVar
            let res = inForAll quanVarStr ia [eMake| &a[&quanVar] = &b[&quanVar] |]
            ret [eMake| !&res |]
        _ -> return Nothing
matrixEq _ = return Nothing


stripStructuralSingle :: MonadConjure m => E -> m (Maybe (E, [Binder]))
stripStructuralSingle [xMatch| [Prim (S nm)] := structural.single.reference |] = do
    mx <- runMaybeT $ lookupReference nm
    case mx of
        Just [xMatch| [Prim (S nm')] := quanVar.name |] | nm == nm' -> return Nothing
        _ -> ret [xMake| reference := [Prim (S nm)] |]
stripStructuralSingle [xMatch| [x] := structural.single |] = ret x
stripStructuralSingle _ = return Nothing

