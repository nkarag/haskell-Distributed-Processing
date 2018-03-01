{-#  LANGUAGE 
     OverloadedStrings 
    ,BangPatterns
    ,DeriveDataTypeable
    ,DeriveGeneric     
   -- ,ScopedTypeVariables
#-}
-- :set -XOverloadedStrings

module Worker  (
    WorkerAck
    ,CommModel (..)
    ,spawnLocalWorkers
    ,getNumOfWorkers
    ,getWorkersWork
  )
  where


--import Debug.Trace
import Control.Concurrent (threadDelay)
import Control.Distributed.Process
import System.Random
import Data.Time.Clock
import Data.Time.Format (formatTime, defaultTimeLocale)
import Data.List (filter, replicate, elemIndex, sortBy)
import Data.Maybe (fromJust)
import Data.Binary
import GHC.Generics
import Data.Typeable

-- | Wroker acknowledgment, sent to coordinator that work is finished.
type WorkerAck = String

-- | Define Communication model between workers.
data CommModel = Naive | MasterClock | Lamport deriving (Eq, Show)


-- | Define message send by a worker
data WorkerMsg = WorkerMsg {
    msgdata :: Double -- ^ a deterministic random number n ∈ (0, 1]
    ,pid :: ProcessId -- ^ the process id of the worker
    ,genTstamp :: String    -- ^ timestamp of when message was generated
    ,genTstamp_psec :: Integer  -- ^ timestamp of when message was generated (for ordering purposes)
} deriving (Eq, Show, Generic, Typeable)

-- Necessary in order to be able to send WorkerMsg to other Processes
instance Binary WorkerMsg


-- | Spawn W workers at local node
spawnLocalWorkers :: 
      CommModel -- ^ Communication model to be used
  ->  Int  -- ^ Number of workers to spawn  
  ->  Process () -- ^ Work for workers to do
  ->  Process [ProcessId] -- ^ Output: list of spawned process ids
spawnLocalWorkers cmodel numOfWs work = do
    case cmodel of
      Naive -> do
        pidsList <- mapM (\_ -> spawnLocal work) (replicate numOfWs 'w') 
        return pidsList
      MasterClock -> do 
        return []
      Lamport -> do 
        return []

-- | Get Number of workers to spawn from a configuration file
getNumOfWorkers :: IO (Int)
getNumOfWorkers = return $ (3::Int)

getWorkersPids :: [ProcessId] -> Process ([ProcessId])
getWorkersPids pids = return pids

getMessage :: WorkerMsg -> Process (WorkerMsg)
getMessage m = return m

-- | Define work for each worker
getWorkersWork :: 
      Int -- ^ send time (sec)
  ->  Int -- ^ grace period (sec)
  ->  Int -- ^ seed for random generator
  ->  ProcessId -- ^ Coordinators Id
  ->  Process ()
getWorkersWork stime gperiod seed coordPid = do
  -- wait to read list of workers Process Ids sent from coordinator
  wPids <- receiveWait [match getWorkersPids]

  -- Debug
  say $ "Debug (worker): " ++ "Have read list of workers pids: " ++ show wPids

  -- create random number generator with the input seed
  let gen = mkStdGen seed

  -- Loop: The following code must be executed for stime only
  say $ "Debug (worker): Starting sending messages ..."
  currentTime <- liftIO getCurrentTime
  sendwork gen currentTime wPids

  -- Loop: Now go on to read your message queue for gperiod of time. At the end print result
  say $ "Debug (worker): Starting reading messages ..."
  --liftIO $ putStrLn $ "Debug (worker): Starting reading messages ..."
  currentTime2 <- liftIO getCurrentTime
  --let 
    --accumulator = 0 :: Double
    --msgCounter = 0 :: Int
  --(new_msgCnt, new_accumVal) <- readwork currentTime2 accumulator msgCounter []

  msgList <- readwork currentTime2 [] -- accumulator msgCounter []

  -- sort message list based on msg generation time time 
  let 
    sortedMsgls = sortBy (\m1 m2 -> (genTstamp_psec m1) `compare` (genTstamp_psec m2)) msgList
    -- compute final result over sorted list
    (i, sum_result) = foldr (\msg (cnt, accumv) -> (cnt + 1, (accumv + (fromIntegral $ cnt + 1) * (msgdata msg)) :: Double)) (0,0) sortedMsgls

  --liftIO $ hFlush stdout
  --liftIO $ hFlush stderr

  -- say $ "Debug (worker): I have finished reading messages : (" ++ (show new_msgCnt) ++ ", " ++ (show new_accumVal) ++ ")"  
  --liftIO $ putStrLn $ "I have finished reading messages"
  self <- getSelfPid
  -- print result
  liftIO $ putStrLn $ "I am worker " ++  show self ++ " and my FINAL result is: (" ++ show i ++ "," ++ show sum_result ++ ")"

  -- send acknowledgment to Coordinator that I have finished
  -- self <- getSelfPid
  send coordPid $ "From worker " ++ show self ++ " OK!"

  liftIO $ threadDelay 1000000

  terminate

  where
    sendwork :: StdGen -> UTCTime -> [ProcessId] -> Process ()
    sendwork g timeStart wPids = do 
      let
        -- get random value in [0,1) 
        r =  random g
        m = (fst r) :: Double
        newgen = snd r
        -- (m::Double, newgen) = random g
      --say $ "Debug (worker): I have generated random number: " ++ show m

      -- construct worker message
      self <- getSelfPid
      currTime <- liftIO getCurrentTime
      let 
        formattedCurrTime = formatTime defaultTimeLocale "%d/%m/%y %T" currTime
        tm =  diffTimeToPicoseconds $ utctDayTime currTime
        msg = WorkerMsg {   msgdata = if m == 0 then 1.0 else m  -- transform 0s to 1s in order to comply with the (0,1] requirement
                            ,pid = self
                            ,genTstamp = formattedCurrTime
                            ,genTstamp_psec = tm
                          }

        -- send m to all other workers
        -- recipients =  filter (\pid -> pid /= self) wPids 
        
        -- send message to ALL nodes including yourself
        recipients = wPids
      mapM_ (\pid -> send pid msg 
                -- do send pid msg; liftIO $ putStrLn $ "Send a message to " ++ show pid 
            ) recipients
      --say $ "Debug (worker): I have broadcasted message to ALL nodes: " ++ show msg


      -- loop if still within send time, i.e,. currentTime - timeStart <= sendTime
      currTime <- liftIO getCurrentTime 
     -- say $ "currTime = " ++ show currTime
     -- say $ "addUTCTime (realToFrac stime) timeStart" ++ (show $ addUTCTime (realToFrac stime) timeStart)

      if currTime < addUTCTime (realToFrac stime) timeStart   
        then -- loop 
          do
            --liftIO $ threadDelay 100000 
            sendwork newgen timeStart wPids
        else  
          do
            say $ "Debug (worker): I have finished sending out messages" 
            return ()

    readwork :: UTCTime  -- -> Double -> Int 
                  -> [WorkerMsg] -> Process [WorkerMsg] -- -> Process (Int, Double)
    readwork timeStart msgls = do -- accumVal msgCnt msgls = do 
      -- loop if still within gperiod time, i.e,. currentTime - timeStart <= gperiod
      currTime <- liftIO getCurrentTime  
      -- if diffUTCTime currTime timeStart <= realToFrac gperiod
      {-say $ "Debug (worker) : timeStart = " ++ show timeStart
      say $ "Debug (worker) : currTime = " ++ show currTime
      say $ "Debug (worker) : diffUTCTime currTime timeStart = " ++ (show $ diffUTCTime currTime timeStart)
      say $ "Debug (worker) : realToFrac gperiod = " ++ (show $ realToFrac gperiod)-}
      -- Debug
      --say $ "currTime = " ++ show currTime
      --say $ "addUTCTime (realToFrac gperiod) timeStart" ++ (show $ addUTCTime (realToFrac gperiod) timeStart)

      if currTime < addUTCTime (realToFrac gperiod) timeStart -- diffUTCTime currTime timeStart < realToFrac gperiod -- currTime < addUTCTime (realToFrac gperiod) timeStart  
        then -- loop 
          do             
            -- read a single message
            msg <- receiveWait [match getMessage]
            -- msg <- receiveTimeout gperiod [match getMessage]
            --say $ "Debug (worker): I have read #" ++ show (msgCnt + (1::Int) ) ++ " message :" ++ show msg
            
            say $ "Debug (worker): I have read #" ++ show (length msgls) ++ " message :" ++ show msg

            -- add message to message list
            let new_msgls = msg:msgls

            -- accumulate sum
            {-let
              new_msgCnt = msgCnt + (1::Int) 
              new_accumVal = (accumVal + (fromIntegral new_msgCnt) * (msgdata msg)) :: Double-}

            -- self <- getSelfPid  
            -- liftIO $ putStrLn $ "I am worker " ++  show self ++ " and my result (so far and unsorted) is: (" ++ show new_msgCnt ++ "," ++ show new_accumVal ++ ")"

            --liftIO $ threadDelay 1000000                 
            -- loop
            readwork timeStart new_msgls -- new_accumVal new_msgCnt new_msgls
        else
            do
              say $ "Debug (worker) : last iteration in readwork"
              return msgls

              {-let
                -- sort message list based on sent time 
                sortedMsgls = sortBy (\m1 m2 -> (sendTstamp_psec m1) `compare` (sendTstamp_psec m2)) msgls
                -- compute final result over sorted list
                -- sum_result = foldr (\msg accum -> (accum + (fromIntegral $ fromJust $ elemIndex msg sortedMsgls) * (msgdata msg)) :: Double) 0 sortedMsgls
                (i, sum_result) = foldr (\msg (cnt, accumv) -> (cnt + 1, (accumv + (fromIntegral $ cnt + 1) * (msgdata msg)) :: Double)) (0,0) sortedMsgls
              --return (msgCnt, accumVal)
              return (length sortedMsgls, sum_result)-}

      {--- loop if still within gperiod time, i.e,. currentTime - timeStart <= gperiod
      currTime <- liftIO getCurrentTime  
      -- if diffUTCTime currTime timeStart <= realToFrac gperiod
      say $ "currTime = " ++ show currTime
      say $ "addUTCTime (realToFrac gperiod) timeStart" ++ (show $ addUTCTime (realToFrac gperiod) timeStart)

      if currTime <= addUTCTime (realToFrac gperiod) timeStart  
        then -- loop 
          do
            liftIO $ threadDelay 350000                 
            readwork timeStart new_accumVal new_msgCnt
        else  -- print final result
          do
            {-say $ "Debug (worker): I have finished reading messages"
            self <- getSelfPid
            -- print result
            liftIO $ putStrLn $ "I am worker " ++  show self ++ " and my result is: (" ++ show new_msgCnt ++ "," ++ show new_accumVal ++ ")"-}
            return (new_msgCnt, new_accumVal)-}


{-    readwork :: UTCTime -> Double -> Int -> Process (Int, Double)
    readwork timeStart accumVal msgCnt = do 
      -- read a single message
      --msg <- receiveWait [match getMessage]
      -- message <- receiveTimeout gperiod [match getMessage]
      message <- (expectTimeout gperiod) :: Process (Maybe WorkerMsg) 
      case message of
        Just msg -> do
          say $ "Debug (worker): I have read #" ++ show (msgCnt + (1::Int) ) ++ " message :" ++ show msg

          -- accumulate sum
          let
            new_msgCnt = msgCnt + (1::Int) 
            new_accumVal = (accumVal + (fromIntegral new_msgCnt) * (msgdata msg)) :: Double

          self <- getSelfPid  
          liftIO $ putStrLn $ "I am worker " ++  show self ++ " and my result is: (" ++ show new_msgCnt ++ "," ++ show new_accumVal ++ ")"
                
          -- loop if still within gperiod time, i.e,. currentTime - timeStart <= gperiod
          currTime <- liftIO getCurrentTime  
          -- if diffUTCTime currTime timeStart <= realToFrac gperiod
          say $ "currTime = " ++ show currTime
          say $ "addUTCTime (realToFrac gperiod) timeStart" ++ (show $ addUTCTime (realToFrac gperiod) timeStart)

          if currTime <= addUTCTime (realToFrac gperiod) timeStart  
            then -- loop 
              do
                liftIO $ threadDelay 200000                 
                readwork timeStart new_accumVal new_msgCnt
            else  -- print final result
                return (new_msgCnt, new_accumVal)
        Nothing -> do
          say $ "inside Nothing"
          return (msgCnt, accumVal)
-}



{-    -- Spawn another worker on the local node
    echoPid <- spawnLocal $ forever $ do
      -- Test our matches in order against each message in the queue
      receiveWait [match logMessage, match replyBack]

    -- The `say` function sends a message to a process registered as "logger".
    -- By default, this process simply loops through its mailbox and sends
    -- any received log message strings it finds to stderr.

  
    send echoPid "hello"
    self <- getSelfPid
    send echoPid (self, "hello")

    -- `expectTimeout` waits for a message or times out after "delay"
    m <- expectTimeout 1000000
    case m of
      -- Die immediately - throws a ProcessExitException with the given reason.
      Nothing  -> die "nothing came back!"
      Just s -> say $ "got " ++ s ++ " back!"
-}

