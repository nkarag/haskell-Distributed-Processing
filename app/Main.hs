module Main where

import Worker
import Control.Concurrent (threadDelay)
import Control.Monad (forever)
import Control.Distributed.Process
import Control.Distributed.Process.Node
--import Control.Distributed.Process.Closure
import Network.Transport.TCP (createTransport, defaultTCPParameters)
import System.Environment

-- stack exec -- iohktest &> output.txt
-- stack exec -- iohktest --send-for 3 --wait-for 5 --seed 7 --cmodel 1 --num-workers 5 2>&1 | tee output.txt


--remotable ['naiveCommModelUncurried, 'lamportCommModelUncurried]

--myRemoteTable :: RemoteTable
--myRemoteTable = Main.__remoteTable initRemoteTable


main :: IO ()
main = do
    args <- getArgs
    -- Process input arguments
    let 
        sendTime = (read $ args!!1) ::Int
        gracePeriod = (read $ args!!3)::Int
        seed = (read $ args!!5)::Int
        comm_model = case (read $ args!!7)::Int of
                        1 -> Naive 
                        2 -> MasterClock
                        3 -> Lamport
        numOfWorkers = (read $ args!!9)::Int

    putStrLn "\n====================================="
    putStrLn "  Program execution setup:"
    putStrLn $ "      sendTime = " ++ (show sendTime)
    putStrLn $ "      gracePeriod = " ++ (show gracePeriod)
    putStrLn $ "      seed = " ++ (show seed)
    putStrLn $ "      comm_model = " ++ (show comm_model)
    putStrLn $ "      numOfWorkers = " ++ (show numOfWorkers)
    putStrLn "=====================================\n"

    -- Create a Node
    Right t <- createTransport "127.0.0.1" "10501" (\s -> ("127.0.0.1","10501")) defaultTCPParameters
    node <- newLocalNode t initRemoteTable -- myRemoteTable -- initRemoteTable

    -- spawn W worker nodes (ie nodes that send and receive messages)
    runProcess node $ do
        -- how many workers to spawn?
        -- w <- liftIO $ getNumOfWorkers
        let w = numOfWorkers

        -- spawn workers
        self <- getSelfPid
        workersls <- spawnLocalWorkers w $ getWorkersWork sendTime gracePeriod seed self comm_model
        --workersls <- spawnRemoteWorkers w (take w $ repeat node) $ getWorkersWorkRemote sendTime gracePeriod seed self comm_model

        -- send to workers the list of workers' pids
        mapM_ (\pid -> send pid workersls) workersls

        -- debug 
        say $ "Debug (Coordinator): " ++ (show $ length workersls) ++ " workers have been spawned: " ++ show workersls ++ "\n Waiting for them to finish work..."

        -- wait...
        --liftIO $ threadDelay $ (sendTime + gracePeriod)

        -- Print worker Acks
        liftIO $ putStrLn "\n\n\n --------- \nWorkers' acknowledgments follow:"

        -- Wait for workers acknowledgement that work has been completed
        waitForWorkersToFinish workersls (sendTime + gracePeriod + 1)

        -- Print worker Acks
        -- liftIO $ putStrLn "Workers' acknowledgments follow:"
        -- liftIO $ mapM_ putStrLn wAcks

        -- Without the following delay, the process sometimes exits before the messages are exchanged        
        liftIO $ threadDelay $ (sendTime + gracePeriod)*500000

-- | Waits specified time to read workers' acknowledgments that have finsihed work from message queue 
-- Prints ack to screen
waitForWorkersToFinish :: 
        [ProcessId] -- ^ list of workers pids
    ->  Int -- ^ seconds to wait
    ->  Process ()  
waitForWorkersToFinish workers timeToWait = do 
    -- liftIO $ putStrLn $ "Debug: length = " ++ (show $ length workers)
    
    liftIO $ threadDelay $ timeToWait
    -- _ <- receiveWait (take (length workers) (repeat (match getworkerAck)) )    
    -- read all messages in the message queue      
    mapM_ (\_ -> receiveWait [match getworkerAck]) $ take (length workers) (repeat "hi!")
    

    -- liftIO $ putStrLn ack    
    return ()
    
    {-wAck <- receiveTimeout timeToWait (take (length workers) (repeat (match getworkerAck)) ) -- [match getworkerAck] -- (replicate (length workers) $ match getworkerAck) 

    case wAck of
        Nothing -> do 
            liftIO $ putStrLn $ "No worker ack received in " ++ (show timeToWait) ++ " secs!"
            return ()
        Just ack -> do
            -- liftIO $ putStrLn ack 
            return ()-}     

getworkerAck :: WorkerAck -> Process (WorkerAck)
getworkerAck ack = do
    liftIO $ putStrLn ack
    return ack

{-

-- simple example

import Network.Transport.TCP (createTransport, defaultTCPParameters)
import Control.Distributed.Process
import Control.Distributed.Process.Node

import System.Environment (getArgs, setEnv)
import System.IO

{-import System.Console.Haskeline as HL
import System.Console.Haskeline.IO as HLIO

import Control.Exception (bracketOnError)-}

-- This import is for liftIO of the MonadIO class
import Control.Monad.IO.Class


main :: IO ()
main = do
  Right t <- createTransport "127.0.0.1" "10501" (\s -> ("127.0.0.1","10501")) defaultTCPParameters
  node <- newLocalNode t initRemoteTable

  _ <- runProcess node $ do
    -- get our own process id
    self <- getSelfPid
    send self "hello"
    hello <- expect :: Process String
    liftIO $ putStrLn hello
  return ()-}



{-

  -- another example

replyBack :: (ProcessId, String) -> Process ()
replyBack (sender, msg) = send sender msg

logMessage :: String -> Process ()
logMessage msg = say $ "handling " ++ msg

main :: IO ()
main = do
  Right t <- createTransport "127.0.0.1" "10501" (\s -> ("127.0.0.1","10501")) defaultTCPParameters
  node <- newLocalNode t initRemoteTable
  runProcess node $ do
    -- Spawn another worker on the local node
    echoPid <- spawnLocal $ forever $ do
      -- Test our matches in order against each message in the queue
      receiveWait [match logMessage, match replyBack]

    -- The `say` function sends a message to a process registered as "logger".
    -- By default, this process simply loops through its mailbox and sends
    -- any received log message strings it finds to stderr.

    say "send some messages!"
    send echoPid "hello"
    self <- getSelfPid
    send echoPid (self, "hello")

    -- `expectTimeout` waits for a message or times out after "delay"
    m <- expectTimeout 1000000
    case m of
      -- Die immediately - throws a ProcessExitException with the given reason.
      Nothing  -> die "nothing came back!"
      Just s -> say $ "got " ++ s ++ " back!"

    -- Without the following delay, the process sometimes exits before the messages are exchanged.
    liftIO $ threadDelay 2000000
  -}
