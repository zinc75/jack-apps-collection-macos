import Control.Monad {- base -}

import Sound.Osc.Fd {- hosc -}
import Sound.Osc.Transport.Fd.Udp {- hosc -}

rju_osc_p :: Int
rju_osc_p = 57130

rju_osc_udp :: IO Udp
rju_osc_udp = openUdp "127.0.0.1" rju_osc_p

with_rju_osc :: (Udp -> IO ()) -> IO ()
with_rju_osc = void . withTransport rju_osc_udp

printer :: Transport t => t -> IO ()
printer fd = do
  sendMessage fd (message "/receive" [int32 0x10])
  forever (do m <- recvMessage_err fd
              print m)

main :: IO ()
main = with_rju_osc printer
