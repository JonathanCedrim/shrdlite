module DataTypes where

import qualified Data.Map        as M
import           ShrdliteGrammar

type Id = String

data Goal = And [Goal]
          | Or [Goal]
          | MoveObj Id Relation Id
          | TakeObj Id deriving (Eq, Show)

type Utterance = [String]
type World = [[Id]]
type Objects = M.Map Id Object
type Plan = [String]
data Strategy = AStar | BFS | LowerCost | PartialOrderPlanner

getPositions :: [[Id]] -> M.Map Id (Int,Int)
getPositions = snd .
    foldl (\(cx,m) stack ->
          (cx+1,snd $ foldl (\(cy,m') elem ->
                      (cy-1,M.insert elem (cx,cy) m')) (length stack,m) stack))
    (0,M.empty)

-- | Equality of two objects.
(~==) :: Object -> Object -> Bool
(Object sz1 c1 f1) ~== (Object sz2 c2 f2) = (cmpSz sz1 sz2) && (cmpCol c1 c2) && (cmpForm f1 f2)
  where
    cmpSz s1 s2   = s1 == AnySize || s2 == AnySize || s1 == s2
    cmpCol c1 c2  = c1 == AnyColor || c2 == AnyColor || c1 == c2
    cmpForm f1 f2 = f1 == AnyForm || f2 == AnyForm || f1 == f2

getObject :: String -> Objects -> Object
getObject "Floor" _ = error "Can't retrieve the object Floor"
getObject id1 objs   = maybe (error "getObject") id (M.lookup id1 objs)

-- | Makes sure that the given object fulfills the relation with the
-- second one.
validRelationship :: World -> Id -> Relation -> Id -> Bool
validRelationship w id1 rel id2 =
  case rel of
    Ontop   -> checkOnTop
    Inside  -> checkOnTop
    Above   -> checkAbove
    Under   -> checkUnder
    Rightof -> checkRight
    Leftof  -> checkLeft
    Beside  -> checkBeside
  where
    getStack "Floor" = error "Can't retrieve the stack number of a Floor"
    getStack id = maybe (error "getStack") fst (M.lookup id positions)
    getPositionInStack "Floor" = error "Can't retrieve the position in the stack of the Floor"
    getPositionInStack id = maybe (error "getPositionInStack") snd
                                  (M.lookup id positions)
    checkOnTop = (id2 == "Floor" && getPositionInStack id1 == 1)
                 ||
                 (id2 /= "Floor" && getStack id1 == getStack id2
                 && getPositionInStack id1 == getPositionInStack id2 + 1)
    checkAbove = (id2 == "Floor")
                 ||
                 getStack id1 == getStack id2
                 && getPositionInStack id1 > getPositionInStack id2
    checkUnder = (id1 == "Floor") || (getStack id1 == getStack id2
                 && getPositionInStack id1 < getPositionInStack id2)
    checkLeft  = getStack id1 < getStack id2
    checkRight = getStack id1 > getStack id2
    checkBeside = abs (getStack id1 - getStack id2) == 1
    positions  = DataTypes.getPositions w

-- | Checks if it is possible to put id1 in relation to id2.
--  The only case where can be a problem is when it attempts to
--  put an object over another.
validMovement :: Objects -> Id -> Id -> Relation -> Bool
validMovement info id1 id2 Ontop = canBeOn id1 id2
  where
    canBeOn _ "Floor" = True
    canBeOn a b | a `isLargerThan` b = False
                | isBall a = isBox b -- Or is floor, but that's checked beforehand
                | isBall b = False
                | isBox b  = not (isPyramid a) || not (isPlank a) || b `isLargerThan` id1
                | isBox a  = a `sameSize` b && (isTable b || isPlank b || (isLarge id1 && isBrick id2))
                | otherwise = True
    isBall    a    = getForm a == Ball
    isBrick   a    = getForm a == Brick
    isPyramid a    = getForm a == Pyramid
    isPlank a      = getForm a == Plank
    isBox a        = getForm a == Box
    isTable a      = getForm a == Table
    isLargerThan a b = go (getSize a) (getSize b)
      where
        go Small _   = False
        go Large sz2 = sz2 == Small
        go _ _       = error "isLargerThan error: Can't process AnySize"
    sameSize a b = getSize a == getSize b
    isLarge a    = getSize a == Large
    getObject a  = maybe (error $ "getObject" ++ show a) id (M.lookup a info)
    getForm a    = let (Object _ _ f) = getObject a
                  in f
    getSize a    = let (Object sz _ _ )  = getObject a
                  in sz
validMovement _ _ "Floor" Leftof  = False
validMovement _ _ "Floor" Rightof = False
validMovement _ _ "Floor" Beside  = False
validMovement _ _ "Floor" Under   = False
validMovement _ "Floor" _ _       = False
validMovement _ _ _ _             = True
