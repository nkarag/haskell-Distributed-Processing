{-#  LANGUAGE 
     OverloadedStrings 
    ,BangPatterns
    ,DeriveDataTypeable
    ,DeriveGeneric  
   -- ,TemplateHaskell   
   -- ,ScopedTypeVariables
#-}
-- :set -XOverloadedStrings

module Worker  (
    WorkerAck
    ,CommModel (..)
    ,spawnLocalWorkers
    ,spawnRemoteWorkers
    ,getNumOfWorkers
    ,getWorkersWork
    --,getWorkersWorkRemote
    ,naiveCommModelUncurried
    ,lamportCommModelUncurried
  )
  where


--import Debug.Trace
import Control.Concurrent (threadDelay)
import Control.Distributed.Process
import Control.Distributed.Process.Closure
import Control.Distributed.Process.Node
import System.Random
import Data.Time.Clock
import Data.Time.Format (formatTime, defaultTimeLocale)
import Data.List (filter, replicate, elemIndex, sortBy, maximum)
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


-- | Define message with Lamport timestamp send by a worker
data WorkerMsgLmp = 
  WorkerMsgLmp {
    msgdataLmp :: Double -- ^ a deterministic random number n ∈ (0, 1]
    ,pidLmp :: ProcessId -- ^ the process id of the worker
    ,lamportTstamp :: Int    -- ^ The Lamport timestamp a simple sequence number indicating when message was generated
  } 
  | EmptyMsg 
  deriving (Eq, Show, Generic, Typeable)

-- Necessary in order to be able to send WorkerMsg to other Processes
instance Binary WorkerMsgLmp


-- | Spawn W workers at local node
spawnRemoteWorkers :: 
      Int  -- ^ Number of workers to spawn  
  ->  [LocalNode]  -- ^ list of worker Nodes
  ->  Closure (Process ()) -- ^ Work for workers to do
  ->  Process [ProcessId] -- ^ Output: list of spawned process ids
spawnRemoteWorkers numOfWs nodesls work = do
        pidsList <- mapM (\nd -> spawn (localNodeId nd) work) nodesls 
        return pidsList

-- | Spawn W workers at W nodes
spawnLocalWorkers :: 
      Int  -- ^ Number of workers to spawn  
  ->  Process () -- ^ Work for workers to do
  ->  Process [ProcessId] -- ^ Output: list of spawned process ids
spawnLocalWorkers numOfWs work = do
        pidsList <- mapM (\_ -> spawnLocal work) (replicate numOfWs 'w') 
        return pidsList


-- | Get Number of workers to spawn from a configuration file
getNumOfWorkers :: IO (Int)
getNumOfWorkers = return $ (3::Int)

getWorkersPids :: [ProcessId] -> Process ([ProcessId])
getWorkersPids pids = return pids

getMessage :: WorkerMsg -> Process (WorkerMsg)
getMessage m = return m

getMessageLmp :: WorkerMsgLmp -> Process WorkerMsgLmp
getMessageLmp m = return m

-- | Define work for each worker
getWorkersWork :: 
      Int -- ^ send time (sec)
  ->  Int -- ^ grace period (sec)
  ->  Int -- ^ seed for random generator
  ->  ProcessId -- ^ Coordinators Id
  ->  CommModel -- ^ Communication Model
  ->  Process ()
getWorkersWork stime gperiod seed coordPid cmodel = do
    case cmodel of
      Naive -> naiveCommModel stime gperiod seed coordPid
      MasterClock -> return ()
      Lamport -> lamportCommModel stime gperiod seed coordPid


-- | Define work for each worker
{-getWorkersWorkRemote :: 
      Int -- ^ send time (sec)
  ->  Int -- ^ grace period (sec)
  ->  Int -- ^ seed for random generator
  ->  ProcessId -- ^ Coordinators Id
  ->  CommModel -- ^ Communication Model
  ->  Closure (Process ()) 
getWorkersWorkRemote stime gperiod seed coordPid cmodel = do
    case cmodel of
      Naive -> $(mkClosure 'naiveCommModelUncurried) (stime, gperiod, seed, coordPid)
      -- MasterClock -> return ()
      Lamport -> $(mkClosure 'lamportCommModelUncurried) (stime, gperiod, seed, coordPid)-}


lamportCommModelUncurried ::
      (Int ,Int ,Int ,ProcessId) -> Process ()
lamportCommModelUncurried (stime, gperiod, seed, coordPid) = lamportCommModel stime gperiod seed coordPid

-- | Lamport Communication Model: Ordering of messages is based on the Leslie Lamport paper:
-- https://lamport.azurewebsites.net/pubs/time-clocks.pdf
lamportCommModel::
      Int -- ^ send time (sec)
  ->  Int -- ^ grace period (sec)
  ->  Int -- ^ seed for random generator
  ->  ProcessId -- ^ Coordinators Id
  ->  Process ()
lamportCommModel stime gperiod seed coordPid = do
  -- wait to read list of workers Process Ids sent from coordinator
  wPids <- receiveWait [match getWorkersPids]

  -- Debug
  say $ "Debug (worker): " ++ "Have read list of workers pids: " ++ show wPids

  -- initialise current maximum sequence
  let currMaxTstamp = 0 :: Int

  -- create random number generator with the input seed
  let gen = mkStdGen seed

  -- start send / receive work for send time. Returns a message list
  currentTime <- liftIO getCurrentTime
  msgList <- sendReceiveWork currentTime stime gen currMaxTstamp wPids []

    -- get whatever unreceived messages (for gperiod of secs) and create final message list
  currentTime2 <- liftIO getCurrentTime
  msgListFinal <- finalizeMsgList currentTime2 gperiod msgList
  
  -- sort final list based on Lamport timestamp and calculate result
  -- sort message list based on msg generation time time 
  let 
    sortedMsgls = sortBy (\m1 m2 -> 
                              case (lamportTstamp m1) `compare` (lamportTstamp m2) of
                                EQ -> (pidLmp m1) `compare` (pidLmp m2)
                                _  -> (lamportTstamp m1) `compare` (lamportTstamp m2)

                          ) msgListFinal
    -- compute final result over sorted list
    (i, sum_result) = foldr (\msg (cnt, accumv) -> (cnt + 1, (accumv + (fromIntegral $ cnt + 1) * (msgdataLmp msg)) :: Double)) (0,0) sortedMsgls

  self <- getSelfPid
  -- print result
  liftIO $ putStrLn $ "I am worker " ++  show self ++ " and my FINAL result is: (" ++ show i ++ "," ++ show sum_result ++ ")"

  -- send ack to coordinator and terminate
  send coordPid $ "From worker " ++ show self ++ " OK. Bye!"

  liftIO $ threadDelay 1000000

  terminate

  return ()
  where
    sendReceiveWork :: UTCTime -> Int -> StdGen -> Int -> [ProcessId] -> [WorkerMsgLmp] -> Process [WorkerMsgLmp]
    sendReceiveWork timeStart stime gen currMaxTstamp wPids msgls = do

      -- Prepare for sending out a message:
      self <- getSelfPid
      let        
        -- get random value in [0,1) 
        r =  random gen
        m = (fst r) :: Double
        newgen = snd r
      
        -- construct message to be sent
        msg_out = WorkerMsgLmp { msgdataLmp = if m == 0 then 1.0 else m  -- transform 0s to 1s in order to comply with the (0,1] requirement
                                ,pidLmp = self
                                ,lamportTstamp = currMaxTstamp
                          }
      
      -- send message to ALL worker nodes including yourself
      let  recipients = wPids

      -- send m to all other workers
      -- let recipients =  filter (\pid -> pid /= self) wPids 

      mapM_ (\pid -> send pid msg_out) recipients
      say $ "Debug (worker): I have broadcasted message to ALL nodes: " ++ show msg_out


      --liftIO $ threadDelay $ 1000

      -- We need to find the max timestamp seen so far. So we have to read the whole message queue
      -- Get the length of the message queue
      procInfoMaybe <- getProcessInfo self
      let msgQueueLength = case procInfoMaybe of
              Just pinfo -> infoMessageQueueLength pinfo
              Nothing -> 0

      say $ "Debug (worker): The length of the message queue is: " ++ (show msgQueueLength)

      -- read all messages in the message queue      
      msg_in_ls <- mapM (\_ -> receiveWait [match getMessageLmp]) $ take (msgQueueLength) (repeat "hi!")
      
      {--- read a single message
      msg_in <- receiveWait [match getMessageLmp]
      say $ "Debug (worker): I have read message: " ++ show msg_in-}
      
      say $ "Debug (worker): I have read " ++ (show $ length msg_in_ls) ++ " messages"
      
      let 
        -- find max timestamp in the list of just read messages 
        maxFromMsgQueue = maximum [lamportTstamp msgin | msgin <- msg_in_ls]

        -- Compare this with current maximum and get timestamp of message generation for next message to be sent
        newMaxTstamp =  if (maxFromMsgQueue) > currMaxTstamp
                              then (maxFromMsgQueue) + (1::Int)
                              else currMaxTstamp + (1::Int)
        -- finally, concat just read message list with the current message list
        new_msgls = msgls ++ msg_in_ls

      {-let 
        -- add message to current list
        new_msgls = msg_in : msg_out : msgls

        -- get timestamp of message generation for next message to be sent
        newMaxTstamp =  if (lamportTstamp msg_in) > currMaxTstamp
                              then (lamportTstamp msg_in) + (1::Int)
                              else currMaxTstamp + (1::Int)-}

         -- loop if still within send time, i.e,. currentTime - timeStart <= sendTime
      currTime <- liftIO getCurrentTime 
      if currTime < addUTCTime (realToFrac stime) timeStart   
        then -- loop 
          do
            --liftIO $ threadDelay 100000 
            sendReceiveWork timeStart stime newgen newMaxTstamp wPids new_msgls
        else  
          do
            say $ "Debug (worker): I have finished sending out messages" 
            return new_msgls

    finalizeMsgList :: UTCTime -> Int -> [WorkerMsgLmp] -> Process [WorkerMsgLmp]
    finalizeMsgList timeStart gperiod msgls = do 
      -- read a single message (do a not blocking read)
      maybe_msg_in <- receiveTimeout 0 [match getMessageLmp]
      let
        msg_in = case maybe_msg_in of
          Just m -> m 
          Nothing -> EmptyMsg 

      self <- getSelfPid      
      let 
        -- add message to current list
        new_msgls = if msg_in == EmptyMsg then msgls else msg_in : msgls

      -- loop if still within gperiod time, i.e,. currentTime - timeStart <= gperiod
      currTime <- liftIO getCurrentTime  
      --say $ "currTime = " ++ show currTime
      --say $ "addUTCTime (realToFrac gperiod) timeStart" ++ (show $ addUTCTime (realToFrac gperiod) timeStart)

      if currTime < addUTCTime (realToFrac gperiod) timeStart -- diffUTCTime currTime timeStart < realToFrac gperiod -- currTime < addUTCTime (realToFrac gperiod) timeStart  
        then -- loop 
          finalizeMsgList timeStart gperiod new_msgls
        else          
            do
              say $ "Debug (worker) : last iteration in finalizeMsgList"
              return new_msgls            

naiveCommModelUncurried ::
  (Int ,Int ,Int ,ProcessId) -> Process ()
naiveCommModelUncurried (stime, gperiod, seed, coordPid) = naiveCommModel stime gperiod seed coordPid

-- | Naive approach communication model:
-- Ordering of messages is based on each nodes system time.
naiveCommModel :: 
      Int -- ^ send time (sec)
  ->  Int -- ^ grace period (sec)
  ->  Int -- ^ seed for random generator
  ->  ProcessId -- ^ Coordinators Id
  ->  Process ()
naiveCommModel stime gperiod seed coordPid = do
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
  send coordPid $ "From worker " ++ show self ++ " OK. Bye!"

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
            self <- getSelfPid 
            -- Get the length of the message queue
            procInfoMaybe <- getProcessInfo self
            let msgQueueLength = case procInfoMaybe of
                    Just pinfo -> infoMessageQueueLength pinfo
                    Nothing -> 0

            say $ "Debug (worker): The length of the message queue is: " ++ (show msgQueueLength)

            {-msg_in_ls <-  if msgQueueLength /= 0 
                            then
                              -- read all messages in the message queue      
                              mapM (\_ -> receiveWait [match getMessage]) $ take (msgQueueLength) (repeat "hi!")
                            else 
                              return []-}

            msg_in_ls <- mapM (\_ -> receiveWait [match getMessage]) $ take (msgQueueLength) (repeat "hi!")

            -- read a single message
            --msg <- receiveWait [match getMessage]
            
            -- msg <- receiveTimeout gperiod [match getMessage]
            --say $ "Debug (worker): I have read #" ++ show (msgCnt + (1::Int) ) ++ " message :" ++ show msg
            
            --say $ "Debug (worker): I have read #" ++ show (length msgls + 1) ++ " message :" ++ show msg

            say $ "Debug (worker): I have read " ++ show (length msg_in_ls) ++ " messages" 
            -- add message to message list
            --let new_msgls = msg:msgls
            let new_msgls = if msg_in_ls == [] then msgls else  msgls ++ msg_in_ls

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

