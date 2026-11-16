{-

- read /time Osc messages sent by rju-osc
- write /text Osc-Json messages to websocket

-}


import Control.Monad {- base -}
import System.Environment {- base -}

import qualified Network.WebSockets as W {- websockets -}

import qualified Music.Theory.Opt as T {- hmt -}
import qualified Music.Theory.Time.Notation as T {- hmt -}

import Sound.Osc.Fd {- hosc -}
import Sound.Osc.Transport.Fd.Udp {- hosc -}

import Sound.Osc.Type.Json.Micro {- hosc-json -}

ws_work :: Udp -> W.Connection -> IO ()
ws_work u c = do
  m <- recvMessage u
  case m of
    Just (Message "/time" [Double x]) -> do
      let msg = message "/text" [string "txt",string (T.minsec_pp (T.fsec_to_minsec x))]
          js = json_encode_value (encode_message msg)
      W.sendTextData c js
    _ -> return ()

ws_proc :: Udp -> W.PendingConnection -> IO ()
ws_proc u rq = do
  c <- W.acceptRequest rq
  putStrLn "transport-ws: connect"
  forever (ws_work u c)

main :: IO ()
main = do
  a <- getArgs
  let h = T.opt_scan_def a ("h","127.0.0.1") -- "192.168.1.7"
      w = T.opt_scan_read a ("w",9160) -- json-ws.05.js
      p = T.opt_scan_read a ("p",57130) -- rju-osc
  print ("h,w,p",h,w,p)
  withTransport
    (openUdp h p)
    (\u -> do
        sendMessage u (message "/receive" [int32 0x10])
        putStrLn "WAIT"
        W.runServer h w (ws_proc u))
