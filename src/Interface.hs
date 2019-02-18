{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE LambdaCase #-}

module Interface where

import Expr
import Path
import Spec

import Opt
import Problem

import Graphics.Gloss.Interface.IO.Game hiding (Path)
import qualified Graphics.Gloss.Interface.IO.Game as Gloss
import qualified Data.Maybe as Maybe
import Control.Arrow ((***))
import Control.Monad.Trans.RWS
import Data.Monoid (First(..))
import Data.Map (Map)
import qualified Data.Map as Map
import qualified Data.Ord as Ord
-- import Data.Sequence (Seq, ViewL(..), ViewR(..))
-- import qualified Data.Sequence as Seq

data Editor = Editor
  { edSpec   :: ShapeType            -- Spec, but single shape definition
  , edDoc    :: Env Float            -- Doc, but single shape instance
  , edDrag   :: Maybe Handle -- handle currently being dragged, if any
  -- , edCursor :: Point
  -- , edScale  :: Float
  -- , edActive :: ActiveHandles -- Handle name
  -- , edOpt    :: Maybe Params
  }
-- R as Float or Double?
-- * gloss uses Float

-- type ActiveHandles = Seq String

-- Editor defaults {{{

initEditor :: ShapeType -> Env Float -> Editor
initEditor st env = Editor
  { edSpec   = st
  , edDoc    = env
  , edDrag   = Nothing
  -- , edCursor = (0,0)
  -- , edScale  = 1
  -- , edActive = Seq.empty
  -- , edOpt    = Nothing
  }

{-
scaleEditor :: Float -> Editor -> Editor
scaleEditor s e = e { edScale = s * edScale e }
-}

cursorRadius :: Float
cursorRadius = 2

-- }}}

-- Rendering {{{

drawEditor :: Float -> Editor -> IO Picture
drawEditor sc ed =
  return
  $ scale sc sc
  $ pictures
  [ drawShape st env
  , drawHandles st env
  -- , drawCursor curs
  ]
  where
  st     = edSpec ed
  env    = edDoc ed
  -- curs   = edCursor ed
  -- active = edActive ed

drawShape :: ShapeType -> Env Float -> Picture
drawShape st env =
  drawEval renderPath
  $ traverse (evalWithShape st env)
  $ shapeRender st

drawEval :: (a -> Picture) -> Either EvalErr a -> Picture
drawEval = either (renderMsg . show)

drawHandles :: ShapeType -> Env Float -> Picture
drawHandles st env =
  drawEval
  ( foldMap drawHandle
  ) $ evalHandles st env

drawHandle :: Point -> Picture
drawHandle p =
  uncurry translate p
  $ color hColor
  $ circle cursorRadius
  where
  hColor = greyN 0.5

{-
  where
  hColor, cFocus, cActive, cInactive :: Color
  hColor = case Seq.viewl active of
    h' :< hs
      | h == h' 
      -> cFocus
      | any (h ==) hs
      -> cActive
    _ -> cInactive
  cFocus    = blendColors red orange
  cInactive = greyN 0.5
  cActive   = blendColors cFocus cInactive
-}

{-
drawCursor :: Point -> Picture
drawCursor curs =
  uncurry translate curs
  $ color
    ( blendColors blue green
    )
  $ circle cursorRadius
-}

renderMsg :: String -> Picture
renderMsg msg =
  translate 10 (-20)
  $ scale s s
  $ color red
  $ text msg
  where
  s = 0.15

accumPicture :: Bool -> Point -> ([Point] -> [Point]) -> Picture -> Picture
accumPicture close c acc p =
  if length ps < 2
  then p
  else mappend p $
    if close
    then polygon ps
    else line ps
  where
  ps = acc [c]

renderPath :: Path Float -> Picture
renderPath (Path close cs) =
  accumPicture close c acc p
  where
  (c,acc,p) = foldl (execCmd close) ((0,0),id,mempty) cs

execCmd :: Bool
  -> (Point,([Point] -> [Point]),Picture)
  -> Cmd Float
  -> (Point,([Point] -> [Point]),Picture)
execCmd close (c,acc,p) = \case
  MoveTo isAbs x' y' ->
    ( movePt isAbs (x',y') c
    , id
    , accumPicture close c acc p
    )
  LineTo isAbs x' y' ->
    ( movePt isAbs (x',y') c
    , (c:) . acc
    , p
    )

type Move = (Bool,Vector) -- Abs/Rel, movement

mkPolygon :: [Move] -> Picture
mkPolygon s =
  polygon
  $ snd
  $ execRWS (processSegment s) () (0,0)

mkLines :: [(Move,[Move])] -> Picture
mkLines ss =
  foldMap line
  $ snd
  $ execRWS (processLines ss) () (0,0)
  where
  l :: Float
  l = -10

processLines :: [(Move,[Move])] -> RWS () [[Point]] Point ()
processLines = mapM_ $ \((isAbs,p'),s) -> do
  modify $ if isAbs
    then const p'
    else addPt p'
  mapRWS (onThd (:[]))
    $ processSegment s
  where
  onThd f (x,y,z) = (x,y,f z)

processSegment :: [Move] -> RWS () [Point] Point ()
processSegment = mapM_ $ \(isAbs,p') -> do
  get >>= tell . (:[])
  modify $ movePt isAbs p'

-- }}}

-- Events {{{

handleEvent :: FilePath -> Float -> Event -> Editor -> IO Editor
handleEvent logPath sc ev ed
  -- mouse movement
  | EventMotion (unscalePt sc -> curs) <- ev
  , Just h <- dragging
  = do writeLog logPath $ unwords
         [ "drag" , h , show $ fst curs , show $ snd curs ]
       return $! ed
         { edDoc = moveHandle st env h curs
         }

  -- handle dragging
  | EventKey (MouseButton LeftButton) Down _ (unscalePt sc -> curs) <- ev
  , Right hs <- evalHandles st env
  , Just h <- nearestWithin cursorRadius curs hs
  = do writeLog logPath $ unwords
         [ "click" , h , show $ fst curs , show $ snd curs ]
       return $! ed
         { edDrag = Just h }
  | EventKey (MouseButton LeftButton) Up _ (unscalePt sc -> curs) <- ev
  , Just h <- dragging
  = do writeLog logPath $ unwords
         [ "release" , h , show $ fst curs , show $ snd curs ]
       return $! ed
         { edDrag = Nothing }

  | otherwise
  = return ed
  where
  st       = edSpec ed
  env      = edDoc ed
  dragging = edDrag ed

writeLog :: FilePath -> String -> IO ()
writeLog logPath ((++ "\n") -> msg) = do
  putStr msg
  appendFile logPath msg

-- }}}

-- Timestep {{{

stepEditor :: Float -> Editor -> IO Editor
stepEditor = const return

{-
  | Just (h,curs) <- edDrag ed
  = do -- putStrLn $ "dragging handle " ++ show h
       let (env',info) = moveHandle st env h curs
       -- putStrLn info
       return ed
         { edDoc = env'
         }
  | otherwise
  = return ed
  where
  st  = edSpec ed
  env = edDoc ed
-}

-- }}}



-- Handle Utils {{{

evalHandles :: ShapeType -> Env Float -> Either EvalErr (Env Point)
evalHandles st env =
  traverse (\(x,y) -> (,) <$> ev x <*> ev y)
  $ shapeHandles st
  where
  ev = evalWithShape st env

{-
activeHandles :: Point -> ShapeType -> Env Float -> ActiveHandles
activeHandles curs st env =
  either (const Seq.empty)
    ( Map.foldMapWithKey $ \h p ->
      if inRadius cursorRadius curs p
      then Seq.singleton h
      else Seq.empty
    )
  $ evalHandles st env
-}

{-
seqFwd, seqBwd :: Seq a -> Seq a
seqFwd s
  | x :< xs <- Seq.viewl s
  = xs Seq.|> x
  | otherwise
  = Seq.empty

seqBwd s
  | xs :> x <- Seq.viewr s
  = x Seq.<| xs
  | otherwise
  = Seq.empty
-}

-- }}}

-- Point Utils {{{

scalePt :: Float -> Point -> Point
scalePt s = (s *) *** (s *)

unscalePt :: Float -> Point -> Point
unscalePt = scalePt . recip

addPt :: Point -> Point -> Point
addPt (x,y) = (x +) *** (y +)

negPt :: Point -> Point
negPt = negate *** negate

subPt :: Point -> Point -> Point
subPt p = addPt p . negPt

normSqrPt :: Point -> Float
normSqrPt (x,y) = x ^ 2 + y ^ 2

movePt :: Bool -> Point -> Point -> Point
movePt isAbs p
  | isAbs = const p
  | otherwise = addPt p

{-
inRadius :: Float -> Point -> Point -> Bool
inRadius r (x,y) (x',y') =
  r ^ 2 >= (x' - x) ^ 2 + (y' - y) ^ 2
-}

nearestWithin :: Float -> Point -> Env Point -> Maybe String
nearestWithin r p =
  fmap fst
  . minimumByWithKey (const id)
  . Map.filter (<= r ^ 2)
  . fmap (normSqrPt . subPt p)

minimumByWithKey :: Ord b => (k -> a -> b) -> Map k a -> Maybe (k,b)
minimumByWithKey f =
  Map.foldlWithKey
  ( \mkb k a ->
    let b = f k a
        p = (k,b)
    in
    maybe (Just p)
    ( \p'@(_,b') -> Just
      $ if b' > b
        then p
        else p'
    ) mkb
  )
  Nothing

-- }}}

-- Color Utils {{{

blendColors :: Color -> Color -> Color
blendColors = mixColors 0.5 0.5

-- }}}

