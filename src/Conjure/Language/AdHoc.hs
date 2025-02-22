module Conjure.Language.AdHoc where

import Conjure.Prelude
import Conjure.UserError
import Conjure.Language.Type
import Conjure.Language.Name
import Conjure.Language.Pretty

-- aeson
import qualified Data.Aeson as JSON
import qualified Data.Aeson.Types as JSON ( Value )
import qualified Data.HashMap.Strict as M       -- unordered-containers
import qualified Data.Vector as V               -- vector

-- scientific
import Data.Scientific ( floatingOrInteger )


class ExpressionLike a where
    fromInt :: Integer -> a
    fromIntWithTag :: Integer -> IntTag -> a
    intOut :: MonadFail m => Doc -> a -> m Integer

    fromBool :: Bool -> a
    boolOut :: MonadFail m => a -> m Bool

    fromList :: [a] -> a
    listOut :: MonadFail m => a -> m [a]

class ReferenceContainer a where
    fromName :: Name -> a
    nameOut :: MonadFail m => a -> m Name

class DomainContainer a dom where
    fromDomain :: dom a -> a
    domainOut :: MonadFail m => a -> m (dom a)

class CanBeAnAlias a where
    isAlias :: a -> Maybe a

class VarSymBreakingDescription a where
    varSymBreakingDescription :: a -> JSON.Value

class (:<) a b where
    inject :: a -> b
    project :: MonadFail m => b -> m a

data MiniZincData = MZNBool Bool
                  | MZNInt Integer
                  | MZNArray (Maybe String) [MiniZincData] -- index if any, then data
                  | MZNSet [MiniZincData]
                  | MZNNamed [(Name, MiniZincData)]
    deriving (Eq, Ord, Show)

instance Pretty MiniZincData where
    pretty (MZNBool x) = pretty x
    pretty (MZNInt x) = pretty x
    pretty (MZNArray index xs) =
        let
            nestedPretty (MZNArray _ ys) = prettyList id "," ys
            nestedPretty y = pretty y

            fillNothingIndices (MZNArray Nothing ys) = MZNArray (Just $ "1.." ++ show (length ys)) (map fillNothingIndices ys)
            fillNothingIndices (MZNArray (Just index2) ys) = MZNArray (Just index2) (map fillNothingIndices ys)
            fillNothingIndices m@MZNBool{} = m
            fillNothingIndices m@MZNInt{} = m
            fillNothingIndices (MZNSet ys) = MZNSet (map fillNothingIndices ys)
            fillNothingIndices (MZNNamed ys) = MZNNamed [(n, fillNothingIndices y) | (n, y) <- ys]

            calcIndices (MZNArray index2 []) = [index2]
            calcIndices (MZNArray index2 (y:_)) = index2 : calcIndices y
            calcIndices _ = []

            indices = calcIndices $ fillNothingIndices $ MZNArray index xs
            depth = length indices

            args = [pretty i | Just i <- indices] ++ [prettyList prBrackets "," (map nestedPretty xs)]
        in
            "array" <> pretty depth <> "d" <> prettyList prParens "," args
    pretty (MZNSet xs) = prettyList prBraces "," (map pretty xs)
    pretty (MZNNamed xs) = vcat [pretty n <+> "=" <+> pretty x <> ";" | (n,x) <- xs]

class ToFromMiniZinc a where
    toMiniZinc :: MonadUserError m => a -> m MiniZincData
    -- this is what we would use to support data files
    -- fromMiniZinc :: MonadUserError m => M.HashMap Name MiniZincData -> m a

noToMiniZinc :: (MonadUserError m, Pretty a) =>  a -> m b
noToMiniZinc a = userErr1 $ vcat
    [ "Cannot convert the following to MiniZinc syntax:"
    , ""
    , pretty (show a)
    , pretty a
    , ""
    , "Let us know if you need support for this please!"
    , "As a workaround you can use --output-format=json"
    ]

class SimpleJSON a where
    toSimpleJSON :: MonadUserError m => a -> m JSON.Value
    fromSimpleJSON :: MonadUserError m => JSON.Value -> m a

instance SimpleJSON Integer where
    toSimpleJSON = return . toJSON
    fromSimpleJSON x =
        case x of
            JSON.Number y ->
                case floatingOrInteger y of
                    Right z -> return z
                    Left (d :: Double) -> noFromSimpleJSON "Integer" d
            _ -> noFromSimpleJSON "Integer" x

data AsDictionary a b = AsDictionary [(a,b)]

instance (Pretty x, SimpleJSON x, SimpleJSON y) => SimpleJSON (AsDictionary x y) where
    toSimpleJSON (AsDictionary xs) = do
        (ys, asList) <- fmap unzip $ forM xs $ \ (a,b) -> do
            let aStr = stringToText $ renderNormal $ pretty a
            aJSON <- toSimpleJSON a
            bJSON <- toSimpleJSON b
            let abPair = JSON.Array $ V.fromList [aJSON, bJSON]
            case aJSON of
                JSON.Bool{}   -> return (Just (aStr, bJSON), abPair)
                JSON.Number{} -> return (Just (aStr, bJSON), abPair)
                JSON.String{} -> return (Just (aStr, bJSON), abPair)
                _             -> return (Nothing           , abPair)
        let zs = catMaybes ys
        if length ys == length zs
            -- all were suitable as keys, great
            then return $ JSON.Object $ M.fromList zs
            else return $ JSON.Array $ V.fromList asList
    fromSimpleJSON x = noFromSimpleJSON "AsDictionary" x

instance SimpleJSON x => SimpleJSON [x] where
    toSimpleJSON xs = do
        ys <- mapM toSimpleJSON xs
        return $ JSON.Array $ V.fromList ys
    fromSimpleJSON x = noFromSimpleJSON "list" x

instance (SimpleJSON x, SimpleJSON y) => SimpleJSON (x,y) where
    toSimpleJSON (x,y) = do
        x' <- toSimpleJSON x
        y' <- toSimpleJSON y
        return $ JSON.Array $ V.fromList [x', y']
    fromSimpleJSON  x = noFromSimpleJSON "pair" x


noToSimpleJSON :: (MonadUserError m, Pretty a) =>  a -> m b
noToSimpleJSON a = userErr1 $ vcat
    [ "Cannot convert the following to simple JSON:"
    , ""
    , pretty a
    , ""
    , "Let us know if you need support for this please!"
    , "As a workaround you can use --output-format=astjson"
    ]


noFromSimpleJSON :: (MonadUserError m, Pretty a, Show a) => String -> a -> m b
noFromSimpleJSON src a = userErr1 $ vcat
    [ "Cannot convert this JSON to Essence yet."
    , ""
    , pretty a
    , pretty (show a)
    , ""
    , "Source:" <+> pretty src
    , ""
    , "Let us know if you need support for this please!"
    , "As a workaround you can use --output-format=astjson"
    ]

