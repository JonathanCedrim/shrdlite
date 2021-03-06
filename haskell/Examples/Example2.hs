module Examples.Example2 where

import Shrdlite
import Plan
import Interpreter
import ShrdliteGrammar
import CombinatorParser
import Data.Map as M
import DataTypes
  
worldE  :: World
worldE   = [["wb"],[],["xb","bb","yb","lb"],["rbox"]]
           

objects :: Objects
objects = M.fromList [ ("xb",Object Large Black Plank)
		     , ("bb",Object Small Blue Pyramid)
		     , ("yb",Object Large Yellow Brick)
		     , ("lb",Object Large White Brick)
		     , ("wb",Object Large White Ball)
		     , ("rbox",Object Large Red Box)
                     ]

pos :: Map Id (Int,Int)
pos = M.fromList [ ("xb",(2,1))
                 , ("bb",(2,2))
                 , ("yb",(2,3))
                 , ("lb",(2,4))
                 , ("wb",(0,1))
                 , ("rbox",(3,1))]
                                
       
utterance =["put", "the", "white", "ball", "on", "the", "black", "plank"]


worldS = WState { _holding     = Nothing,
                  _positions   = pos,
                  _world       = worldE,
                  _objectsInfo = objects
		}
