{-# LANGUAGE OverloadedStrings #-}

-- Implicit CAD. Copyright (C) 2011, Christopher Olah (chris@colah.ca)
-- Released under the GNU GPL, see LICENSE

module Graphics.Implicit.Export.PolylineFormats where

import Graphics.Implicit.Definitions

import Graphics.Implicit.Export.TextBuilderUtils

import Text.Blaze.Svg.Renderer.Text (renderSvg)
import Text.Blaze.Svg
import Text.Blaze.Svg11 ((!),docTypeSvg,g,polyline,toValue)
import Text.Blaze.Internal (stringValue)
import qualified Text.Blaze.Svg11.Attributes as A

import Data.List (foldl')
import qualified Data.List as List

svg :: [Polyline] -> Text
svg plines = renderSvg . svg11 . svg' $ plines
    where  
      (xmin, xmax, ymin, ymax) = (minimum xs, maximum xs, minimum ys, maximum ys)
           where (xs,ys) = unzip (concat plines)
      
      svg11 content = docTypeSvg ! A.version "1.1" 
                                 ! A.width  (stringValue $ show (xmax-xmin) ++ "mm")
                                 ! A.height (stringValue $ show (ymax-ymin) ++ "mm")
                                 ! A.viewbox (stringValue $ unwords . map show $ [0,0,xmax-xmin,ymax-ymin])
                                 $ content
      -- The reason this isn't totally straightforwards is that svg has different coordinate system
      -- and we need to compute the requisite translation.
      svg' [] = mempty 
      -- When we have a known point, we can compute said transformation:
      svg' polylines = thinBlueGroup $ mapM_ poly polylines

      poly line = polyline ! A.points pointList 
          where pointList = toValue $ toLazyText $ mconcat [bf (x-xmin) <> "," <> bf (ymax - y) <> " " | (x,y) <- line]

      -- Instead of setting styles on every polyline, we wrap the lines in a group element and set the styles on it:
      thinBlueGroup = g ! A.stroke "rgb(0,0,255)" ! A.strokeWidth "1" ! A.fill "none" -- obj

hacklabLaserGCode :: [Polyline] -> Text
hacklabLaserGCode polylines = toLazyText $ gcodeHeader <> mconcat (map interpretPolyline orderedPoylines) <> gcodeFooter
    where 
      orderedPoylines = 
            snd . unzip 
            . List.sortBy (\(a,_) (b, _) -> compare a b)
            . map (\x -> (polylineRadius x, x))
            $ polylines
      polylineRadius [] = 0
      polylineRadius polyline = max (xmax - xmin) (ymax - ymin) where
           ((xmin, xmax), (ymin, ymax)) = polylineRadius' polyline
           polylineRadius' [(x,y)] = ((x,x),(y,y))
           polylineRadius' ((x,y):ps) = ((min x xmin,max x xmax),(min y ymin, max y ymax))
                where ((xmin, xmax), (ymin, ymax)) = polylineRadius' ps
      gcodeHeader = mconcat [
                     "(generated by ImplicitCAD, based of hacklab wiki example)\n"
                    ,"M63 P0 (laser off)\n"
                    ,"G0 Z0.002 (laser off)\n"
                    ,"G21 (units=mm)\n"
                    ,"F400 (set feedrate)\n"
                    ,"M3 S1 (enable laser)\n\n"]
      gcodeFooter = mconcat [
                     "M5 (disable laser)\n"
                    ,"G00 X0.0 Y0.0 (move to 0)\n"
                    ,"M2 (end)"]
      gcodeXY :: ℝ2 -> Builder
      gcodeXY (x,y) = mconcat ["X", buildTruncFloat x, " Y", buildTruncFloat y]
                      
      interpretPolyline (start:others) = mconcat [
                                          "G00 ", gcodeXY start
                                         ,"\nM62 P0 (laser on)\n"
                                         ,mconcat [ "G01 " <> gcodeXY point <> "\n" | point <- others]
                                         ,"M63 P0 (laser off)\n\n"
                                         ]
      interpretPolyline [] = mempty 
