{-# LANGUAGE DeriveGeneric #-}
module Plan  where

import           DataTypes
import           ShrdliteGrammar

import qualified Data.Heap       as PQ
import qualified Data.Map        as M
import qualified Data.Set        as S

import           Data.Hashable
import           GHC.Generics    (Generic)

import           Data.List       (foldl')
import           Data.Maybe      (isJust)

-- | Action that can be performed.
data Action = DropA Int | TakeA Int


instance Show Action where
  show (DropA n) = "drop " ++ show n
  show (TakeA n) = "pick " ++ show n

-- | WorldState for planning algorithm.
data WorldState = WState { _holding     :: Maybe Id,
                           _positions   :: M.Map Id (Int, Int),
                           _world       :: World,
                           _objectsInfo :: M.Map Id Object
			 } deriving (Generic)

instance Hashable WorldState where
  hashWithSalt s (WState holding _ world _) = s `hashWithSalt` holding
                                              `hashWithSalt` world


-- | Calculates all the possible actions to take in the current world.
actions :: WorldState -> [Action]
actions (WState holding _ world info) =
  case holding of
    Nothing     -> map (TakeA . snd) $ filter ((>0) . length . fst) $ zip world [0..]

    Just obj    -> map (DropA . snd) $ filter (canBeOn obj . fst) $
                   zip (map (\l -> if null l then "Floor" else head l) world)   [0..]
    where
    canBeOn _ "Floor" = True
    canBeOn id1 id2
      | size1 > size2 = False
      | form1 == Ball = form2 == Box -- Or is floor, but that's checked beforehand
      | form2 == Ball = False
      | form2 == Box  = not ((form1 == Box) || (form1 == Pyramid) || (form1 == Plank)) || size2 > size1
      | form1 == Box  = size1 == size2
                        &&    ( form2 == Table
                             || form2 == Plank
                             || (size1 == Large && form2 == Brick))
      | otherwise = True
      where
        Just (Object size1 _ form1) =  M.lookup id1 info
        Just (Object size2 _ form2) =  M.lookup id2 info



-- Checks if a given world satisfies a world
isSolution :: WorldState -> Goal -> Bool
isSolution worldState goal =
  case goal of
    MoveObj id rel id2 
      | isJust (_holding worldState) -> False
      | otherwise ->
        M.member id (_positions worldState)
        &&
        let Just (x1,y1) = M.lookup id (_positions worldState)
            Just (x2,y2) =
              case id2 of
                "Floor" -> return (x1,0)
                _       -> M.lookup id2 (_positions worldState)
	in case rel of
            Beside  -> abs (x1 - x2) == 1
            Leftof  -> x1 < x2
            Rightof -> x1 > x2
            Above   -> x1 == x2 && y1 > y2
            Ontop   -> x1 == x2 && y1 - y2 == 1
            Inside  -> x1 == x2 && y1 - y2 == 1
            Under   -> x1 == x2 && y1 < y2

    TakeObj id ->
      case _holding worldState of
	Just id2 -> id == id2
	Nothing -> False

    And goals -> and $ map (isSolution worldState) goals
    Or goals  -> or  $ map (isSolution worldState) goals
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
  maximum $ map (heuristicAStar worldState) goals
heuristicAStar worldState (Or goals) =
  minimum $ map (heuristicAStar worldState) goals
heuristicAStar worldState (TakeObj id1) = 
  2 * (length (_world worldState !! x) - y)
  where Just (x,y) = M.lookup id1 (_positions worldState)
heuristicAStar worldState goal@(MoveObj id1 rel id2)
  | isSolution worldState goal = 0
  | otherwise = 
    case rel of
      Ontop -> hid1 + hid2
        where
          hid1 = let Just (x,y)  = M.lookup id1 (_positions worldState)
                     movesToFree = (length (_world worldState !! x) - y)
                 in case _holding worldState of
                      Nothing  -> movesToFree 
                      Just obj
                        | obj == id1 -> 1
                        | otherwise  -> movesToFree 
                               
                                       
          hid2 = if id2 == "Floor" then
                    minimum (map length (_world worldState))
                 else
                   let Just (x,y) = M.lookup id2 (_positions worldState)
                   in (length (_world worldState !! x) - y)

      Above -> hid1 + hid2
        where
          hid1 = let Just (x,y)    = M.lookup id1 (_positions worldState)
                     movesToFree   = (length (_world worldState !! x) - y)
                 in case _holding worldState of
                      Nothing  -> movesToFree  
                      Just obj 
                        | obj == id1 -> 1
                        | otherwise  -> movesToFree 

          hid2 = let Just (x,y)  = M.lookup id2 (_positions worldState)
                     movesToFit  = length (takeWhile
                                                  (\id ->
                                                     id /= id2
                                                      && not (validMovement
                                                              (_objectsInfo worldState)
                                                              id1
                                                              id
                                                              Ontop))
                                                  (_world worldState !! x))
                 in case _holding worldState of
                      Nothing  -> movesToFit 
                      Just obj
                        | obj == id2 -> 1
                        | otherwise  -> movesToFit
          
      Leftof  -> minimum $ [cost1 + cost2 | 
                        (index1, cost1) <- costs1,
                        (index2, cost2) <- costs2,
                        index1 < index2]
      Rightof -> heuristicAStar worldState (MoveObj id2 Leftof id1)
      Beside  -> minimum $ [cost1 + cost2 |
                                  (index1, cost1) <- costs1,
                                  (index2, cost2) <- costs2, 
                                  (abs (index1 - index2) == 1)]
      _ -> 2
      where
      costs1 = zip ([1..]::[Int]) $ calculateCosts id1
      costs2 = zip ([1..]::[Int]) $ calculateCosts id2
      calculateCosts id = map (stackheuristicAStar id) $ _world worldState
      stackheuristicAStar _ [] = 1
      stackheuristicAStar id list = heuristicAStar worldState (MoveObj id Above (last list))
         
cost :: WorldState -> Action -> Int
cost _ _ = 1

-- | Priority holding the heuristic and the cost
newtype Prio = Prio (Int,Int) deriving (Eq)

instance Ord Prio where
    compare (Prio (h1, c1)) (Prio (h2, c2)) = compare (h1+c1) (h2+c2)


-- | Bfs on the tree of worlds
plan :: Strategy -> World -> Maybe Id -> Objects -> Goal -> Maybe (Plan,WorldState)
plan strategy world holding objects goal = go initialQueue S.empty
  where
  	initialWorld     = WState holding (getPositions world) world objects
        initialQueue     = PQ.singleton (PQ.Entry (Prio (0,0))
                                                  (initialWorld,[]))
        heuristic        = case strategy of
                             AStar -> heuristicAStar
                             BFS   -> \_ _ -> 0
                             LowerCost -> \_ _ -> 0

        go queue visited =
          case PQ.viewMin queue of
            Nothing  -> Nothing
            Just (PQ.Entry (Prio (_,oldCost)) (world,oldActions),rest) ->
                 if isSolution world goal then
                   Just ( map show . reverse $ oldActions, world)
                 else
                   go (PQ.union rest (PQ.fromList newWorlds)) newVisited
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
