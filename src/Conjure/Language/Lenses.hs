{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE ViewPatterns #-}

module Conjure.Language.Lenses where

import Conjure.Prelude
import Conjure.Language.Definition
import Conjure.Language.Domain
import Conjure.Language.Type
import Conjure.Language.TypeOf
import Conjure.Language.Expression.Op
import Conjure.Language.Pretty
import Conjure.Language.AdHoc


-- | To use a lens for constructing stuf.
make :: (Proxy Identity -> (a, b)) -> a
make  f = fst (f (Proxy :: Proxy Identity))

-- | To use a lens for deconstructing stuf.
match :: CanBeAnAlias b => (Proxy (m :: * -> *) -> (a, b -> m c)) -> b -> m c
match f = snd (f Proxy)

followAliases :: CanBeAnAlias b => (b -> c) -> b -> c
followAliases m (isAlias -> Just x) = followAliases m x
followAliases m x = m x

tryMatch :: CanBeAnAlias b => (Proxy Maybe -> (a, b -> Maybe c)) -> b -> Maybe c
tryMatch f = match f

matchOr :: CanBeAnAlias b => c -> (Proxy Maybe -> (a, b -> Maybe c)) -> b -> c
matchOr defOut f inp = fromMaybe defOut (match f inp)

matchDef :: CanBeAnAlias b => (Proxy Maybe -> (a, b -> Maybe b)) -> b -> b
matchDef f inp = matchOr inp f inp

matchDefs :: CanBeAnAlias b => [Proxy Maybe -> (a, b -> Maybe b)] -> b -> b
matchDefs fs inp =
    case mapMaybe (`match` inp) fs of
        []      -> inp
        (out:_) -> matchDefs fs out


--------------------------------------------------------------------------------
-- Lenses (for a weird definition of lens) -------------------------------------
--------------------------------------------------------------------------------


opMinus
    :: ( Op x :< x
       , Pretty x
       , MonadFail m
       )
    => Proxy (m :: * -> *)
    -> ( x -> x -> x
       , x -> m (x,x)
       )
opMinus _ =
    ( \ x y -> inject (MkOpMinus (OpMinus x y))
    , \ p -> do
            op <- project p
            case op of
                MkOpMinus (OpMinus x y) -> return (x,y)
                _ -> na ("Lenses.opMinus:" <++> pretty p)
    )


opDiv
    :: ( Op x :< x
       , Pretty x
       , MonadFail m
       )
    => Proxy (m :: * -> *)
    -> ( x -> x -> x
       , x -> m (x,x)
       )
opDiv _ =
    ( \ x y -> inject (MkOpDiv (OpDiv x y))
    , \ p -> do
            op <- project p
            case op of
                MkOpDiv (OpDiv x y) -> return (x,y)
                _ -> na ("Lenses.opDiv:" <++> pretty p)
    )


opMod
    :: ( Op x :< x
       , Pretty x
       , MonadFail m
       )
    => Proxy (m :: * -> *)
    -> ( x -> x -> x
       , x -> m (x,x)
       )
opMod _ =
    ( \ x y -> inject (MkOpMod (OpMod x y))
    , \ p -> do
            op <- project p
            case op of
                MkOpMod (OpMod x y) -> return (x,y)
                _ -> na ("Lenses.opMod:" <++> pretty p)
    )


opPow
    :: ( Op x :< x
       , Pretty x
       , MonadFail m
       )
    => Proxy (m :: * -> *)
    -> ( x -> x -> x
       , x -> m (x,x)
       )
opPow _ =
    ( \ x y -> inject (MkOpPow (OpPow x y))
    , \ p -> do
            op <- project p
            case op of
                MkOpPow (OpPow x y) -> return (x,y)
                _ -> na ("Lenses.opPow:" <++> pretty p)
    )


opNegate
    :: ( Op x :< x
       , Pretty x
       , MonadFail m
       )
    => Proxy (m :: * -> *)
    -> ( x -> x
       , x -> m x
       )
opNegate _ =
    ( inject . MkOpNegate . OpNegate
    , \ p -> do
            op <- project p
            case op of
                MkOpNegate (OpNegate x) -> return x
                _ -> na ("Lenses.opNegate:" <++> pretty p)
    )


opDontCare
    :: ( Op x :< x
       , Pretty x
       , MonadFail m
       )
    => Proxy (m :: * -> *)
    -> ( x -> x
       , x -> m x
       )
opDontCare _ =
    ( inject . MkOpDontCare . OpDontCare
    , \ p -> do
            op <- project p
            case op of
                MkOpDontCare (OpDontCare x) -> return x
                _ -> na ("Lenses.opDontCare:" <++> pretty p)
    )


opDefined
    :: ( Op x :< x
       , Pretty x
       , MonadFail m
       )
    => Proxy (m :: * -> *)
    -> ( x -> x
       , x -> m x
       )
opDefined _ =
    ( inject . MkOpDefined . OpDefined
    , \ p -> do
            op <- project p
            case op of
                MkOpDefined (OpDefined x) -> return x
                _ -> na ("Lenses.opDefined:" <++> pretty p)
    )


opRange
    :: ( Op x :< x
       , Pretty x
       , MonadFail m
       )
    => Proxy (m :: * -> *)
    -> ( x -> x
       , x -> m x
       )
opRange _ =
    ( inject . MkOpRange . OpRange
    , \ p -> do
            op <- project p
            case op of
                MkOpRange (OpRange x) -> return x
                _ -> na ("Lenses.opRange:" <++> pretty p)
    )


opDefinedOrRange
    :: ( Op x :< x
       , Pretty x
       , MonadFail m
       )
    => Proxy (m :: * -> *)
    -> ( (x -> x, x) -> x
       , x -> m (x -> x, x)
       )
opDefinedOrRange _ =
    ( \ (mk, x) -> mk x
    , \ p -> case project p of
        Just (MkOpDefined (OpDefined x)) -> return (inject . MkOpDefined . OpDefined , x)
        Just (MkOpRange   (OpRange   x)) -> return (inject . MkOpRange   . OpRange   , x)
        _                                -> na ("Lenses.opDefinedOrRange" <++> pretty p)
    )


opRestrict
    :: MonadFail m
    => Proxy (m :: * -> *)
    -> ( Expression -> Domain () Expression -> Expression
       , Expression -> m (Expression, Domain () Expression)
       )
opRestrict _ =
    ( \ x d -> inject $ MkOpRestrict $ OpRestrict x (Domain d)
    , followAliases extract
    )
    where
        extract (Op (MkOpRestrict (OpRestrict x (Domain d)))) = return (x, d)
        extract p = na ("Lenses.opRestrict:" <++> pretty p)


opToInt
    :: ( Op x :< x
       , Pretty x
       , MonadFail m
       )
    => Proxy (m :: * -> *)
    -> ( x -> x
       , x -> m x
       )
opToInt _ =
    ( inject . MkOpToInt . OpToInt
    , \ p -> do
            op <- project p
            case op of
                MkOpToInt (OpToInt x) -> return x
                _ -> na ("Lenses.opToInt:" <++> pretty p)
    )


opPowerSet
    :: ( Op x :< x
       , Pretty x
       , MonadFail m
       )
    => Proxy (m :: * -> *)
    -> ( x -> x
       , x -> m x
       )
opPowerSet _ =
    ( inject . MkOpPowerSet . OpPowerSet
    , \ p -> do
            op <- project p
            case op of
                MkOpPowerSet (OpPowerSet x) -> return x
                _ -> na ("Lenses.opPowerSet:" <++> pretty p)
    )


opToSet
    :: ( Op x :< x
       , Pretty x
       , MonadFail m
       )
    => Proxy (m :: * -> *)
    -> ( x -> x
       , x -> m x
       )
opToSet _ =
    ( inject . MkOpToSet . OpToSet
    , \ p -> do
            op <- project p
            case op of
                MkOpToSet (OpToSet x) -> return x
                _ -> na ("Lenses.opToSet:" <++> pretty p)
    )


opToMSet
    :: ( Op x :< x
       , Pretty x
       , MonadFail m
       )
    => Proxy (m :: * -> *)
    -> ( x -> x
       , x -> m x
       )
opToMSet _ =
    ( inject . MkOpToMSet . OpToMSet
    , \ p -> do
            op <- project p
            case op of
                MkOpToMSet (OpToMSet x) -> return x
                _ -> na ("Lenses.opToMSet:" <++> pretty p)
    )


opToRelation
    :: ( Op x :< x
       , Pretty x
       , MonadFail m
       )
    => Proxy (m :: * -> *)
    -> ( x -> x
       , x -> m x
       )
opToRelation _ =
    ( inject . MkOpToRelation . OpToRelation
    , \ p -> do
            op <- project p
            case op of
                MkOpToRelation (OpToRelation x) -> return x
                _ -> na ("Lenses.opToRelation:" <++> pretty p)
    )


opParts
    :: ( Op x :< x
       , Pretty x
       , MonadFail m
       )
    => Proxy (m :: * -> *)
    -> ( x -> x
       , x -> m x
       )
opParts _ =
    ( inject . MkOpParts . OpParts
    , \ p -> do
            op <- project p
            case op of
                MkOpParts (OpParts x) -> return x
                _ -> na ("Lenses.opParts:" <++> pretty p)
    )


opParty
    :: ( Op x :< x
       , Pretty x
       , MonadFail m
       )
    => Proxy (m :: * -> *)
    -> ( x -> x -> x
       , x -> m (x, x)
       )
opParty _ =
    ( \ x y -> inject $ MkOpParty $ OpParty x y
    , \ p -> do
            op <- project p
            case op of
                MkOpParty (OpParty x y) -> return (x,y)
                _ -> na ("Lenses.opParty:" <++> pretty p)
    )


opParticipants
    :: ( Op x :< x
       , Pretty x
       , MonadFail m
       )
    => Proxy (m :: * -> *)
    -> ( x -> x
       , x -> m x
       )
opParticipants _ =
    ( inject . MkOpParticipants . OpParticipants
    , \ p -> do
            op <- project p
            case op of
                MkOpParticipants (OpParticipants x) -> return x
                _ -> na ("Lenses.opParticipants:" <++> pretty p)
    )


opFunctionImage
    :: ( Op x :< x
       , Pretty x
       , MonadFail m
       )
    => Proxy (m :: * -> *)
    -> ( x -> x -> x
       , x -> m (x, x)
       )
opFunctionImage _ =
    ( \ x y -> inject $ MkOpFunctionImage $ OpFunctionImage x y
    , \ p -> do
            op <- project p
            case op of
                MkOpFunctionImage (OpFunctionImage x y) -> return (x,y)
                _ -> na ("Lenses.opFunctionImage:" <++> pretty p)
    )


opRelationProj
    :: ( Op x :< x
       , Pretty x
       , MonadFail m
       )
    => Proxy (m :: * -> *)
    -> ( x -> [Maybe x] -> x
       , x -> m (x, [Maybe x])
       )
opRelationProj _ =
    ( \ x ys -> inject $ MkOpRelationProj $ OpRelationProj x ys
    , \ p -> do
            op <- project p
            case op of
                MkOpRelationProj (OpRelationProj x ys) -> return (x,ys)
                _ -> na ("Lenses.opRelationProj:" <++> pretty p)
    )


opRelationImage
    :: ( Op x :< x
       , Pretty x
       , MonadFail m
       )
    => Proxy (m :: * -> *)
    -> ( x -> [x] -> x
       , x -> m (x, [x])
       )
opRelationImage _ =
    ( \ x ys -> inject $ MkOpRelationProj $ OpRelationProj x (map Just ys)
    , \ p -> do
            op <- project p
            case op of
                MkOpRelationProj (OpRelationProj x ys)
                    | let ys' = catMaybes ys
                    , length ys' == length ys           -- they were all Just's
                    -> return (x,ys')
                _ -> na ("Lenses.opRelationProj:" <++> pretty p)
    )


opIndexing
    :: ( Op x :< x
       , Pretty x
       , MonadFail m
       )
    => Proxy (m :: * -> *)
    -> ( x -> x -> x
       , x -> m (x,x)
       )
opIndexing _ =
    ( \ x y -> inject (MkOpIndexing (OpIndexing x y))
    , \ p -> do
            op <- project p
            case op of
                MkOpIndexing (OpIndexing x y) -> return (x,y)
                _ -> na ("Lenses.opIndexing:" <++> pretty p)
    )


opMatrixIndexing
    :: ( Op x :< x
       , Pretty x
       , TypeOf x
       , MonadFail m
       )
    => Proxy (m :: * -> *)
    -> ( x -> [x] -> x
       , x -> m (x,[x])
       )
opMatrixIndexing _ =
    ( foldl (make opIndexing)
    , \ p -> do
        (m, is) <- go p
        if null is
            then na ("Lenses.opMatrixIndexing:" <+> pretty p)
            else return (m, is)
    )
    where
        go p = case project p of
            Just (MkOpIndexing (OpIndexing x i)) -> do
                ty <- typeOf x
                case ty of
                    TypeMatrix{} -> return ()
                    TypeList{} -> return ()
                    _ -> na ("Lenses.opMatrixIndexing:" <+> pretty p)
                (m,is) <- go x
                return (m, is ++ [i])
            _ -> return (p, [])


opSlicing
    :: ( Op x :< x
       , Pretty x
       , MonadFail m
       )
    => Proxy (m :: * -> *)
    -> ( x -> Maybe x -> Maybe x -> x
       , x -> m (x, Maybe x, Maybe x)
       )
opSlicing _ =
    ( \ x y z -> inject (MkOpSlicing (OpSlicing x y z))
    , \ p -> do
            op <- project p
            case op of
                MkOpSlicing (OpSlicing x y z) -> return (x,y,z)
                _ -> na ("Lenses.opSlicing:" <++> pretty p)
    )


opFlatten
    :: ( Op x :< x
       , Pretty x
       , MonadFail m
       )
    => Proxy (m :: * -> *)
    -> ( x -> x
       , x -> m x
       )
opFlatten _ =
    ( inject . MkOpFlatten . OpFlatten
    , \ p -> do
            op <- project p
            case op of
                MkOpFlatten (OpFlatten x) -> return x
                _ -> na ("Lenses.opFlatten:" <++> pretty p)
    )


opIn
    :: ( Op x :< x
       , Pretty x
       , MonadFail m
       )
    => Proxy (m :: * -> *)
    -> ( x -> x -> x
       , x -> m (x,x)
       )
opIn _ =
    ( \ x y -> inject (MkOpIn (OpIn x y))
    , \ p -> do
            op <- project p
            case op of
                MkOpIn (OpIn x y) -> return (x,y)
                _ -> na ("Lenses.opIn:" <++> pretty p)
    )


opFreq
    :: ( Op x :< x
       , Pretty x
       , MonadFail m
       )
    => Proxy (m :: * -> *)
    -> ( x -> x -> x
       , x -> m (x,x)
       )
opFreq _ =
    ( \ x y -> inject (MkOpFreq (OpFreq x y))
    , \ p -> do
            op <- project p
            case op of
                MkOpFreq (OpFreq x y) -> return (x,y)
                _ -> na ("Lenses.opFreq:" <++> pretty p)
    )


opHist
    :: ( Op x :< x
       , Pretty x
       , MonadFail m
       )
    => Proxy (m :: * -> *)
    -> ( x -> x
       , x -> m x
       )
opHist _ =
    ( inject . MkOpHist . OpHist
    , \ p -> do
            op <- project p
            case op of
                MkOpHist (OpHist x) -> return x
                _ -> na ("Lenses.opHist:" <++> pretty p)
    )


opIntersect
    :: ( Op x :< x
       , Pretty x
       , MonadFail m
       )
    => Proxy (m :: * -> *)
    -> ( x -> x -> x
       , x -> m (x,x)
       )
opIntersect _ =
    ( \ x y -> inject (MkOpIntersect (OpIntersect x y))
    , \ p -> do
            op <- project p
            case op of
                MkOpIntersect (OpIntersect x y) -> return (x,y)
                _ -> na ("Lenses.opIntersect:" <++> pretty p)
    )


opUnion
    :: ( Op x :< x
       , Pretty x
       , MonadFail m
       )
    => Proxy (m :: * -> *)
    -> ( x -> x -> x
       , x -> m (x,x)
       )
opUnion _ =
    ( \ x y -> inject (MkOpUnion (OpUnion x y))
    , \ p -> do
            op <- project p
            case op of
                MkOpUnion (OpUnion x y) -> return (x,y)
                _ -> na ("Lenses.opUnion:" <++> pretty p)
    )


opSubsetEq
    :: ( Op x :< x
       , Pretty x
       , MonadFail m
       )
    => Proxy (m :: * -> *)
    -> ( x -> x -> x
       , x -> m (x,x)
       )
opSubsetEq _ =
    ( \ x y -> inject (MkOpSubsetEq (OpSubsetEq x y))
    , \ p -> do
            op <- project p
            case op of
                MkOpSubsetEq (OpSubsetEq x y) -> return (x,y)
                _ -> na ("Lenses.opSubsetEq:" <++> pretty p)
    )


opEq
    :: ( Op x :< x
       , Pretty x
       , MonadFail m
       )
    => Proxy (m :: * -> *)
    -> ( x -> x -> x
       , x -> m (x,x)
       )
opEq _ =
    ( \ x y -> inject (MkOpEq (OpEq x y))
    , \ p -> do
            op <- project p
            case op of
                MkOpEq (OpEq x y) -> return (x,y)
                _ -> na ("Lenses.opEq:" <++> pretty p)
    )


opNeq
    :: ( Op x :< x
       , Pretty x
       , MonadFail m
       )
    => Proxy (m :: * -> *)
    -> ( x -> x -> x
       , x -> m (x,x)
       )
opNeq _ =
    ( \ x y -> inject (MkOpNeq (OpNeq x y))
    , \ p -> do
            op <- project p
            case op of
                MkOpNeq (OpNeq x y) -> return (x,y)
                _ -> na ("Lenses.opNeq:" <++> pretty p)
    )


opLt
    :: ( Op x :< x
       , Pretty x
       , MonadFail m
       )
    => Proxy (m :: * -> *)
    -> ( x -> x -> x
       , x -> m (x,x)
       )
opLt _ =
    ( \ x y -> inject (MkOpLt (OpLt x y))
    , \ p -> do
            op <- project p
            case op of
                MkOpLt (OpLt x y) -> return (x,y)
                _ -> na ("Lenses.opLt:" <++> pretty p)
    )


opLeq
    :: ( Op x :< x
       , Pretty x
       , MonadFail m
       )
    => Proxy (m :: * -> *)
    -> ( x -> x -> x
       , x -> m (x,x)
       )
opLeq _ =
    ( \ x y -> inject (MkOpLeq (OpLeq x y))
    , \ p -> do
            op <- project p
            case op of
                MkOpLeq (OpLeq x y) -> return (x,y)
                _ -> na ("Lenses.opLeq:" <++> pretty p)
    )


opGt
    :: ( Op x :< x
       , Pretty x
       , MonadFail m
       )
    => Proxy (m :: * -> *)
    -> ( x -> x -> x
       , x -> m (x,x)
       )
opGt _ =
    ( \ x y -> inject (MkOpGt (OpGt x y))
    , \ p -> do
            op <- project p
            case op of
                MkOpGt (OpGt x y) -> return (x,y)
                _ -> na ("Lenses.opGt:" <++> pretty p)
    )


opGeq
    :: ( Op x :< x
       , Pretty x
       , MonadFail m
       )
    => Proxy (m :: * -> *)
    -> ( x -> x -> x
       , x -> m (x,x)
       )
opGeq _ =
    ( \ x y -> inject (MkOpGeq (OpGeq x y))
    , \ p -> do
            op <- project p
            case op of
                MkOpGeq (OpGeq x y) -> return (x,y)
                _ -> na ("Lenses.opGeq:" <++> pretty p)
    )


opOr
    :: ( Op x :< x
       , Pretty x
       , MonadFail m
       )
    => Proxy (m :: * -> *)
    -> ( x -> x
       , x -> m x
       )
opOr _ =
    ( inject . MkOpOr . OpOr
    , \ p -> do
            op <- project p
            case op of
                MkOpOr (OpOr xs) -> return xs
                _ -> na ("Lenses.opOr:" <++> pretty p)
    )


opAnd
    :: ( Op x :< x
       , Pretty x
       , MonadFail m
       )
    => Proxy (m :: * -> *)
    -> ( x -> x
       , x -> m x
       )
opAnd _ =
    ( inject . MkOpAnd . OpAnd
    , \ p -> do
            op <- project p
            case op of
                MkOpAnd (OpAnd xs) -> return xs
                _ -> na ("Lenses.opAnd:" <++> pretty p)
    )


opMax
    :: ( Op x :< x
       , Pretty x
       , MonadFail m
       )
    => Proxy (m :: * -> *)
    -> ( x -> x
       , x -> m x
       )
opMax _ =
    ( inject . MkOpMax . OpMax
    , \ p -> do
            op <- project p
            case op of
                MkOpMax (OpMax xs) -> return xs
                _ -> na ("Lenses.opMax:" <++> pretty p)
    )


opMin
    :: ( Op x :< x
       , Pretty x
       , MonadFail m
       )
    => Proxy (m :: * -> *)
    -> ( x -> x
       , x -> m x
       )
opMin _ =
    ( inject . MkOpMin . OpMin
    , \ p -> do
            op <- project p
            case op of
                MkOpMin (OpMin xs) -> return xs
                _ -> na ("Lenses.opMin:" <++> pretty p)
    )


opImply
    :: ( Op x :< x
       , Pretty x
       , MonadFail m
       )
    => Proxy (m :: * -> *)
    -> ( x -> x -> x
       , x -> m (x,x)
       )
opImply _ =
    ( \ x y -> inject (MkOpImply (OpImply x y))
    , \ p -> do
            op <- project p
            case op of
                MkOpImply (OpImply x y) -> return (x,y)
                _ -> na ("Lenses.opImply:" <++> pretty p)
    )


opNot
    :: ( Op x :< x
       , Pretty x
       , MonadFail m
       )
    => Proxy (m :: * -> *)
    -> ( x -> x
       , x -> m x
       )
opNot _ =
    ( inject . MkOpNot . OpNot
    , \ p -> do
            op <- project p
            case op of
                MkOpNot (OpNot x) -> return x
                _ -> na ("Lenses.opNot:" <++> pretty p)
    )


opProduct
    :: ( Op x :< x
       , Pretty x
       , MonadFail m
       )
    => Proxy (m :: * -> *)
    -> ( x -> x
       , x -> m x
       )
opProduct _ =
    ( inject . MkOpProduct . OpProduct
    , \ p -> do
            op <- project p
            case op of
                MkOpProduct (OpProduct x) -> return x
                _ -> na ("Lenses.opProduct:" <++> pretty p)
    )


opSum
    :: ( Op x :< x
       , Pretty x
       , MonadFail m
       )
    => Proxy (m :: * -> *)
    -> ( x -> x
       , x -> m x
       )
opSum _ =
    ( inject . MkOpSum . OpSum
    , \ p -> do
            op <- project p
            case op of
                MkOpSum (OpSum x) -> return x
                _ -> na ("Lenses.opSum:" <++> pretty p)
    )


opQuantifier
    :: ( Op x :< x
       , Pretty x
       , MonadFail m
       )
    => Proxy (m :: * -> *)
    -> ( (x -> x, x) -> x
       , x -> m (x -> x, x)
       )
opQuantifier _ =
    ( \ (mk, x) -> mk x
    , \ p -> do
            op <- project p
            case op of
                MkOpAnd     (OpAnd     x) -> return (inject . MkOpAnd     . OpAnd     , x)
                MkOpOr      (OpOr      x) -> return (inject . MkOpOr      . OpOr      , x)
                MkOpSum     (OpSum     x) -> return (inject . MkOpSum     . OpSum     , x)
                MkOpProduct (OpProduct x) -> return (inject . MkOpProduct . OpProduct , x)
                MkOpMax     (OpMax     x) -> return (inject . MkOpMax     . OpMax     , x)
                MkOpMin     (OpMin     x) -> return (inject . MkOpMin     . OpMin     , x)
                _ -> na ("Lenses.opQuantifier:" <++> pretty p)
    )


opModifier
    :: ( Op x :< x
       , Pretty x
       , MonadFail m
       )
    => Proxy (m :: * -> *)
    -> ( (x -> x, x) -> x
       , x -> m (x -> x, x)
       )
opModifier _ =
    ( \ (mk, x) -> mk x
    , \ p -> case project p of
        Just (MkOpToSet      (OpToSet      x)) -> return (inject . MkOpToSet      . OpToSet      , x)
        Just (MkOpToMSet     (OpToMSet     x)) -> return (inject . MkOpToMSet     . OpToMSet     , x)
        Just (MkOpToRelation (OpToRelation x)) -> return (inject . MkOpToRelation . OpToRelation , x)
        Just (MkOpParts      (OpParts      x)) -> return (inject . MkOpParts      . OpParts      , x)
        _                                      -> return (id                                       , p)
    )


opAllDiff
    :: ( Op x :< x
       , Pretty x
       , MonadFail m
       )
    => Proxy (m :: * -> *)
    -> ( x -> x
       , x -> m x
       )
opAllDiff _ =
    ( inject . MkOpAllDiff . OpAllDiff
    , \ p -> do
            op <- project p
            case op of
                MkOpAllDiff (OpAllDiff x) -> return x
                _ -> na ("Lenses.opAllDiff:" <++> pretty p)
    )


constantInt
    :: MonadFail m
    => Proxy (m :: * -> *)
    -> ( Integer -> Expression
       , Expression -> m Integer
       )
constantInt _ =
    ( Constant . ConstantInt
    , \ p -> case p of
            (Constant (ConstantInt i)) -> return i
            _ -> na ("Lenses.constantInt:" <++> pretty p)
    )


matrixLiteral
    :: MonadFail m
    => Proxy (m :: * -> *)
    -> ( Type -> Domain () Expression -> [Expression] -> Expression
       , Expression -> m (Type, Domain () Expression, [Expression])
       )
matrixLiteral _ =
    ( \ ty index elems ->
        if null elems
            then Typed (AbstractLiteral (AbsLitMatrix index elems)) ty
            else        AbstractLiteral (AbsLitMatrix index elems)
    , \ p -> do
        ty          <- typeOf p
        (index, xs) <- followAliases extract p
        return (ty, index, xs)
    )
    where
        extract (Constant (ConstantAbstract (AbsLitMatrix index xs))) = return (fmap Constant index, map Constant xs)
        extract (AbstractLiteral (AbsLitMatrix index xs)) = return (index, xs)
        extract (Typed x _) = extract x
        extract (Constant (TypedConstant x _)) = extract (Constant x)
        extract p = na ("Lenses.matrixLiteral:" <+> pretty p)


setLiteral
    :: MonadFail m
    => Proxy (m :: * -> *)
    -> ( Type -> [Expression] -> Expression
       , Expression -> m (Type, [Expression])
       )
setLiteral _ =
    ( \ ty elems ->
        if null elems
            then Typed (AbstractLiteral (AbsLitSet elems)) ty
            else        AbstractLiteral (AbsLitSet elems)
    , \ p -> do
        ty <- typeOf p
        xs <- followAliases extract p
        return (ty, xs)
    )
    where
        extract (Constant (ConstantAbstract (AbsLitSet xs))) = return (map Constant xs)
        extract (AbstractLiteral (AbsLitSet xs)) = return xs
        extract (Typed x _) = extract x
        extract (Constant (TypedConstant x _)) = extract (Constant x)
        extract p = na ("Lenses.setLiteral:" <+> pretty p)


msetLiteral
    :: MonadFail m
    => Proxy (m :: * -> *)
    -> ( Type -> [Expression] -> Expression
       , Expression -> m (Type, [Expression])
       )
msetLiteral _ =
    ( \ ty elems ->
        if null elems
            then Typed (AbstractLiteral (AbsLitMSet elems)) ty
            else        AbstractLiteral (AbsLitMSet elems)
    , \ p -> do
        ty <- typeOf p
        xs <- followAliases extract p
        return (ty, xs)
    )
    where
        extract (Constant (ConstantAbstract (AbsLitMSet xs))) = return (map Constant xs)
        extract (AbstractLiteral (AbsLitMSet xs)) = return xs
        extract (Typed x _) = extract x
        extract (Constant (TypedConstant x _)) = extract (Constant x)
        extract p = na ("Lenses.msetLiteral:" <+> pretty p)


functionLiteral
    :: MonadFail m
    => Proxy (m :: * -> *)
    -> ( Type -> [(Expression,Expression)] -> Expression
       , Expression -> m (Type, [(Expression,Expression)])
       )
functionLiteral _ =
    ( \ ty elems ->
        if null elems
            then Typed (AbstractLiteral (AbsLitFunction elems)) ty
            else        AbstractLiteral (AbsLitFunction elems)
    , \ p -> do
        ty <- typeOf p
        xs <- followAliases extract p
        return (ty, xs)
    )
    where
        extract (Constant (ConstantAbstract (AbsLitFunction xs))) = return [ (Constant a, Constant b) | (a,b) <- xs ]
        extract (AbstractLiteral (AbsLitFunction xs)) = return xs
        extract (Typed x _) = extract x
        extract (Constant (TypedConstant x _)) = extract (Constant x)
        extract p = na ("Lenses.functionLiteral:" <+> pretty p)


sequenceLiteral
    :: MonadFail m
    => Proxy (m :: * -> *)
    -> ( Type -> [Expression] -> Expression
       , Expression -> m (Type, [Expression])
       )
sequenceLiteral _ =
    ( \ ty elems ->
        if null elems
            then Typed (AbstractLiteral (AbsLitSequence elems)) ty
            else        AbstractLiteral (AbsLitSequence elems)
    , \ p -> do
        ty <- typeOf p
        xs <- followAliases extract p
        return (ty, xs)
    )
    where
        extract (Constant (ConstantAbstract (AbsLitSequence xs))) = return (map Constant xs)
        extract (AbstractLiteral (AbsLitSequence xs)) = return xs
        extract (Typed x _) = extract x
        extract (Constant (TypedConstant x _)) = extract (Constant x)
        extract p = na ("Lenses.sequenceLiteral:" <+> pretty p)


relationLiteral
    :: MonadFail m
    => Proxy (m :: * -> *)
    -> ( Type -> [[Expression]] -> Expression
       , Expression -> m (Type, [[Expression]])
       )
relationLiteral _ =
    ( \ ty elems ->
        if null elems
            then Typed (AbstractLiteral (AbsLitRelation elems)) ty
            else        AbstractLiteral (AbsLitRelation elems)
    , \ p -> do
        ty <- typeOf p
        xs <- followAliases extract p
        return (ty, xs)
    )
    where
        extract (Constant (ConstantAbstract (AbsLitRelation xs))) = return (map (map Constant) xs)
        extract (AbstractLiteral (AbsLitRelation xs)) = return xs
        extract (Typed x _) = extract x
        extract (Constant (TypedConstant x _)) = extract (Constant x)
        extract p = na ("Lenses.relationLiteral:" <+> pretty p)


partitionLiteral
    :: MonadFail m
    => Proxy (m :: * -> *)
    -> ( Type -> [[Expression]] -> Expression
       , Expression -> m (Type, [[Expression]])
       )
partitionLiteral _ =
    ( \ ty elems ->
        if null elems
            then Typed (AbstractLiteral (AbsLitPartition elems)) ty
            else        AbstractLiteral (AbsLitPartition elems)
    , \ p -> do
        ty <- typeOf p
        xs <- followAliases extract p
        return (ty, xs)
    )
    where
        extract (Constant (ConstantAbstract (AbsLitPartition xs))) = return (map (map Constant) xs)
        extract (AbstractLiteral (AbsLitPartition xs)) = return xs
        extract (Typed x _) = extract x
        extract (Constant (TypedConstant x _)) = extract (Constant x)
        extract p = na ("Lenses.partitionLiteral:" <+> pretty p)


opTwoBars
    :: ( Op x :< x
       , Pretty x
       , MonadFail m
       )
    => Proxy (m :: * -> *)
    -> ( x -> x
       , x -> m x
       )
opTwoBars _ =
    ( inject . MkOpTwoBars . OpTwoBars
    , \ p -> do
            op <- project p
            case op of
                MkOpTwoBars (OpTwoBars x) -> return x
                _ -> na ("Lenses.opTwoBars:" <++> pretty p)
    )


opPreImage
    :: ( Op x :< x
       , Pretty x
       , MonadFail m
       )
    => Proxy (m :: * -> *)
    -> ( x -> x -> x
       , x -> m (x,x)
       )
opPreImage _ =
    ( \ x y -> inject (MkOpPreImage (OpPreImage x y))
    , \ p -> do
            op <- project p
            case op of
                MkOpPreImage (OpPreImage x y) -> return (x,y)
                _ -> na ("Lenses.opPreImage:" <++> pretty p)
    )


opActive
    :: ( Op x :< x
       , Pretty x
       , MonadFail m
       )
    => Proxy (m :: * -> *)
    -> ( x -> Name -> x
       , x -> m (x,Name)
       )
opActive _ =
    ( \ x y -> inject (MkOpActive (OpActive x y))
    , \ p -> do
            op <- project p
            case op of
                MkOpActive (OpActive x y) -> return (x,y)
                _ -> na ("Lenses.opActive:" <++> pretty p)
    )


opFactorial
    :: ( Op x :< x
       , Pretty x
       , MonadFail m
       )
    => Proxy (m :: * -> *)
    -> ( x -> x
       , x -> m x
       )
opFactorial _ =
    ( inject . MkOpFactorial . OpFactorial
    , \ p -> do
            op <- project p
            case op of
                MkOpFactorial (OpFactorial x) -> return x
                _ -> na ("Lenses.opFactorial:" <++> pretty p)
    )
