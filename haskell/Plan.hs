{-# LANGUAGE DeriveGeneric #-}
module Plan  where

import           DataTypes
import           ShrdliteGrammar

import qualified Data.Heap       as PQ
import qualified Data.Map        as M
import qualified Data.Set        as S

import           Data.List       (foldl')
import           Data.Maybe      (isJust)

import Data.Hashable (hash)
  
-- | Action that can be performed.
data Action = DropA Int | TakeA Int

instance Show Action where
  show (DropA n) = "drop " ++ show n
  show (TakeA n) = "pick " ++ show n


-- | Calculates all the possible actions to take in the current world.
actions :: WorldState -> [Action]
actions worldState@(WState holding _ world info) =
  case holding of
    Nothing     -> [ TakeA n | (stack,n) <- zip world [0..]
                             , length stack > 0]

    Just obj    -> [ DropA n | (stack,n) <- zip world [0..]
                             , let obj2 = if null stack then "Floor"
                                          else head stack
                             , relationValid (_objectsInfo worldState)
                                             obj obj2 Ontop] 
                       

-- Checks if a given world satisfies a goal
isSolution :: WorldState -> Goal -> Bool
isSolution worldState goal =
  case goal of
    MoveObj id rel id2 
      | isJust (_holding worldState) -> False
      | otherwise -> relationHolds worldState id rel id2

    TakeObj id ->
      case _holding worldState of
	Just id2 -> id == id2
	Nothing -> False

    And goals -> all (isSolution worldState) goals
    Or goals  -> any (isSolution worldState) goals

-- Apply an action to a world and get a new world
transition :: WorldState -> Action -> WorldState
transition worldState action =
  case action of
    TakeA n ->
      let id = head (_world worldState !! n)
      in
        WState
           (Just id)
           (_positions worldState)
           (removeFromStackN (_world worldState) n)
           (_objectsInfo worldState)
    DropA n ->
      let Just id = _holding worldState
      in
        WState
	   Nothing
	   (M.insert id (n, length (_world worldState !! n) + 1) (_positions worldState))
           (addToStackN (_world worldState) id n)
           (_objectsInfo worldState)

    where
      removeFromStackN :: [[a]] -> Int -> [[a]]
      removeFromStackN stacks n = concat [ take n stacks
                                         , [tail $ stacks !! n]
                                         , drop (n+1) stacks ]

      addToStackN :: [[a]] -> a -> Int -> [[a]]
      addToStackN stacks elem n = concat [ take n stacks
                                         , [elem : stacks !! n]
                                         , drop (n + 1) stacks ]


heuristicAStar :: WorldState -> Goal -> Int
heuristicAStar worldState (And goals) =
  maximum $  map (heuristicAStar worldState) goals
heuristicAStar worldState (Or goals) =
  minimum $  map (heuristicAStar worldState) goals
heuristicAStar worldState (TakeObj id1) = 
  2 *  (length (_world worldState !! x) - y)
  where
    Just (x,y) = M.lookup id1 (_positions worldState)
heuristicAStar worldState goal@(MoveObj id1 rel id2)
  | isSolution worldState goal = 0
  | otherwise = 
    case rel of
      Ontop -> case _holding worldState of
                 Nothing  ->
                   if id2 /= "Floor"
                      &&
                      relationHolds worldState id2 Above id1 then
                     movesToFreeId1 + 2 * (y1 - y2)
                   else
                     movesToFreeId1 + movesToFreeId2
                 Just obj 
                   | obj == id1 -> movesToFreeId2
                   | otherwise  -> movesToFreeId1 + movesToFreeId2
                      
        where
          movesToFreeId1 = 2 * length (_world worldState !! x1) - y1
          movesToFreeId2 = if id2 == "Floor" then
                             2 * minimum (map length (_world worldState))
                           else
                             2 * length (_world worldState !! x2) - y2
          Just (x1,y1)   =  M.lookup id1 (_positions worldState)
          Just (x2,y2)   =  M.lookup id2 (_positions worldState)


      Above -> case _holding worldState of
                 Nothing  -> movesToFreeId1 + movesToFitId2
                 Just obj
                      | obj == id1 -> movesToFitId2
                      | otherwise  -> movesToFreeId1 + movesToFitId2
        where
          movesToFreeId1   = 2 * length (_world worldState !! x1) - y1
          movesToFitId2    = if id2 == "Floor" then 0
                             else
                               2 * length (takeWhile
                                           (\id ->
                                              id /= id2
                                              && not ( relationValid
                                                      (_objectsInfo worldState)
                                                      id1
                                                      id
                                                      Ontop))
                                           (_world worldState !! x2))
            
          Just (x1,y1)    = M.lookup id1 (_positions worldState)
          Just (x2,y2)    = M.lookup id2 (_positions worldState)
          
      Leftof
        | null h    -> 2
        | otherwise -> minimum h
        where
          h = [cost1 + cost2 | (index1, cost1) <- costs1
                             , (index2, cost2) <- costs2
                             , index1 < index2]

      Beside
        | null h    -> 2
        | otherwise -> minimum h
        where 
          h = [cost1 + cost2 | (index1, cost1) <- costs1
                             , (index2, cost2) <- costs2
                             , abs (index1 - index2) == 1]

      Rightof -> heuristicAStar worldState (MoveObj id2 Leftof id1)
      Under   -> heuristicAStar worldState (MoveObj id2 Above id1)
      Inside  -> heuristicAStar worldState (MoveObj id1 Ontop id2)

      where
        costs1 = zip [1..] $ calculateCosts id1
        costs2 = zip [1..] $ calculateCosts id2
        calculateCosts id = map (stackheuristicAStar id) $ _world worldState
        stackheuristicAStar _ [] = 1
        stackheuristicAStar id list =
          heuristicAStar worldState (MoveObj id Above (last list))
         
cost :: WorldState -> Action -> Int
cost _ _ = 1

-- | Priority holding the heuristic and the cost
newtype Prio = Prio (Int,Int) deriving (Eq)

instance Ord Prio where
    compare (Prio (h1, c1)) (Prio (h2, c2)) = compare (h1+c1) (h2+c2)


-- | Bfs on the tree of worlds
plan :: Strategy -> WorldState -> Goal -> (Maybe (Plan,WorldState),Int)
plan strategy initialWorld goal = go initialStats initialQueue S.empty
  where
        initialQueue     = PQ.singleton (PQ.Entry (Prio (0,0))
                                                  (initialWorld,[]))
        heuristic        = case strategy of
                             AStar     -> heuristicAStar
                             BFS       -> const2 0
        initialStats     = 0
        go stat queue visited =
          case PQ.viewMin queue of
            Nothing  -> (Nothing, stat)
            Just (PQ.Entry (Prio (_,oldCost)) (world,oldActions),rest) ->
                 if isSolution world goal then
                   (Just (map show . reverse $ oldActions, world), stat)
                 else
                   go (stat + 1) (PQ.union rest (PQ.fromList newWorlds)) newVisited
                     where
                       newWorlds =
                         map (\(w,a) -> PQ.Entry
                                        (Prio (heuristic w goal
                                              , cost w (head a) + oldCost))
                                        (w,a))
                          $ filter (\(w,_) -> hash w `S.notMember` visited)
                          $ zip (map (transition world) newActions)
                                (map (:oldActions) newActions)

                       newVisited    = foldl' (\v (PQ.Entry _ (w,_))
                                                 -> S.insert (hash w) v)
                                       visited newWorlds
                       newActions    = actions world

const2 :: a -> b -> c -> a
const2 c = \_ _  -> c
