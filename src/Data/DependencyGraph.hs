module Data.DependencyGraph where

import Data.Function (on)

import Data.Functor ((<&>))

import Data.Map (Map)
import qualified Data.Map as Map

import Data.Set (Set)
import qualified Data.Set as Set

import Data.Text.Lazy (Text)
import qualified Data.Text.Lazy.IO as T (readFile, writeFile)

import Data.Traversable (for)

import Data.GraphViz.Attributes.Complete (Attribute(Label), Label(..))
import Data.GraphViz.Types (parseDotGraph, printDotGraph)
import Data.GraphViz.Types.Canonical

import System.Exit (die)

------------------------------------------------------------------------
-- A node's neighbours

type Node = String
type Label = String

data Neighbours n v = Neighbours
  { value    :: v
  , parents  :: Set n
  , children :: Set n
  } deriving (Show, Functor, Foldable, Traversable)

instance (Ord n, Semigroup v) => Semigroup (Neighbours n v) where
  Neighbours v1 p1 c1 <> Neighbours v2 p2 c2
    = Neighbours (v1 <> v2) (p1 <> p2) (c1 <> c2)

degreeWith :: (Int -> Int -> Int) -> Neighbours n v -> Int
degreeWith f ngh = (f `on` Set.size) (parents ngh) (children ngh)

degree :: Neighbours n v -> Int
degree = degreeWith (+)

type Labels n = Map n Text

------------------------------------------------------------------------
-- Dependency graph

data DependencyGraph n v = DependencyGraph
  { labels   :: Labels n
  , contexts :: Map n (Neighbours n v)
  } deriving (Functor, Foldable, Traversable)


onContexts :: Ord n
           => (Neighbours n v -> Neighbours n w)
           -> (DependencyGraph n v -> DependencyGraph n w)
onContexts f (DependencyGraph labels contexts)
  = DependencyGraph labels (f <$> contexts)


------------------------------------------------------------------------
-- Converting back and forth to a DOT graph

fromDotGraph :: Ord n => DotGraph n -> Maybe (DependencyGraph n ())
fromDotGraph (DotGraph False True _ (DotStmts [] [] nodes edges))
  = do labels <- for nodes $ \case
         DotNode id [Label (StrLabel txt)] -> pure (id, txt)
         _ -> Nothing
       nghbrs <- fmap concat $ for edges $ \case
         DotEdge from to [] -> pure [ (to, Neighbours () mempty (Set.singleton from))
                                    , (from, Neighbours () (Set.singleton to) mempty)
                                    ]
         _ -> Nothing
       pure $ DependencyGraph (Map.fromList labels) (Map.fromListWith (<>) nghbrs)
isDependencyGraph _ = Nothing


toDotGraph :: forall n. Ord n => DependencyGraph n [Attribute] -> DotGraph n
toDotGraph (DependencyGraph labels nghbrs)
  = DotGraph False True Nothing (DotStmts [] [] nodes edges)

  where

    nodes :: [DotNode n]
    nodes = Map.toList labels <&> \ (lbl, nm) ->
      DotNode lbl $ Label (StrLabel nm)
                  : maybe [] value (Map.lookup lbl nghbrs)

    edges :: [DotEdge n]
    edges = flip concatMap (Map.toList nghbrs) $ \ (lbl, nghbr) ->
      flip (DotEdge lbl) [] <$> Set.toList (parents nghbr)

------------------------------------------------------------------------
-- Loading a graph from a file

fromFile :: FilePath -> IO (DependencyGraph String ())
fromFile fp = do
  file <- T.readFile fp
  let grph = parseDotGraph file
  case fromDotGraph grph of
    Nothing -> die "Invalid dependency graph"
    Just deps -> pure deps

toFile :: FilePath -> DependencyGraph String [Attribute] -> IO ()
toFile fp grph = T.writeFile fp (printDotGraph (toDotGraph grph))
