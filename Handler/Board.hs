{-# LANGUAGE TupleSections, OverloadedStrings #-}
module Handler.Board where

import           Import
import           Yesod.Auth
import qualified Data.Text       as T
import           Handler.Delete  (deletePosts)
import           Handler.Captcha (checkCaptcha, recordCaptcha, getCaptchaInfo, updateAdaptiveCaptcha)
import           Handler.Posting
import           AwfulMarkup     (doAwfulMarkup)
--------------------------------------------------------------------------------------------------------- 
getBoardNoPageR :: Text -> Handler Html
getBoardNoPageR board = getBoardR board 0

postBoardNoPageR :: Text -> Handler Html
postBoardNoPageR board = postBoardR board 0
--------------------------------------------------------------------------------------------------------- 
getBoardR :: Text -> Int -> Handler Html
getBoardR board page = do
  muser    <- maybeAuth
  mgroup   <- getMaybeGroup muser
  boardVal <- getBoardVal404 board
  checkViewAccess mgroup boardVal
  let hasAccessToNewThread = checkAccessToNewThread mgroup boardVal
      permissions          = getPermissions mgroup
  ------------------------------------------------------------------------------------------------------- 
  numberOfThreads <- runDB $ count [PostBoard ==. board, PostParent ==. 0]
  let numberFiles       = boardNumberFiles       boardVal
      maxMessageLength  = boardMaxMsgLength      boardVal
      threadsPerPage    = boardThreadsPerPage    boardVal
      previewsPerThread = boardPreviewsPerThread boardVal
      enableCaptcha     = boardEnableCaptcha     boardVal
      boardDesc         = boardDescription       boardVal
      boardLongDesc     = boardLongDescription   boardVal
      geoIpEnabled      = boardEnableGeoIp       boardVal
      ---------------------------------------------------------------------------------
      pages             = [0..pagesFix $ floor $ (fromIntegral numberOfThreads :: Double) / (fromIntegral threadsPerPage :: Double)]
      pagesFix x
        | numberOfThreads > 0 && numberOfThreads `mod` threadsPerPage == 0 = x - 1
        | otherwise                                                      = x
      ---------------------------------------------------------------------------------
      selectThreads    = selectList [PostBoard ==. board, PostParent ==. 0, PostDeleted ==. False]
                         [Desc PostSticked, Desc PostBumped, LimitTo threadsPerPage, OffsetBy $ page*threadsPerPage]
      selectFiles  pId = selectList [AttachedfileParentId ==. pId] []
      selectPreviews t
        | previewsPerThread > 0 = selectList [PostDeletedByOp ==. False, PostBoard ==. board, PostDeleted ==. False,
                                              PostParent ==. postLocalId t] [Desc PostDate, LimitTo previewsPerThread]
        | otherwise             = return []
  -------------------------------------------------------------------------------------------------------
  threadsAndPreviews <- runDB $ selectThreads >>= mapM (\th@(Entity tId t) -> do
                           threadFiles      <- selectFiles tId
                           previewsAndFiles <- selectPreviews t >>= mapM (\pr -> do
                             previewFiles <- selectFiles $ entityKey pr
                             return (pr, previewFiles))
                           postsInThread <- count [PostDeletedByOp ==. False, PostDeleted ==. False,
                                                  PostBoard ==. board, PostParent ==. postLocalId t]
                           return ((th, threadFiles), reverse previewsAndFiles, postsInThread - previewsPerThread))
  ------------------------------------------------------------------------------------------------------- 
  geoIps' <- forM (if geoIpEnabled then threadsAndPreviews else []) $ \((Entity tId t,_),ps,_) -> do
    xs <- forM ps $ \(Entity pId p,_) -> getCountry (postIp p) >>= (\c' -> return (pId, c'))
    c  <- getCountry $ postIp t
    return $ (tId, c):xs
  let geoIps = map (second fromJust) $ filter (isJust . snd) $ concat geoIps'
  -------------------------------------------------------------------------------------------------------
  now       <- liftIO getCurrentTime
  acaptcha  <- lookupSession "acaptcha"
  when (isNothing acaptcha && enableCaptcha && isNothing muser) $ recordCaptcha =<< getConfig configCaptchaLength
  ------------------------------------------------------------------------------------------------------- 
  (formWidget, formEnctype) <- generateFormPost $ postForm numberFiles 
  (formWidget', _)          <- generateFormPost editForm
  nameOfTheBoard   <- extraSiteName <$> getExtra
  maybeCaptchaInfo <- getCaptchaInfo
  msgrender        <- getMessageRender

  defaultLayout $ do
    setUltDestCurrent
    setTitle $ toHtml $ T.concat [nameOfTheBoard, " — ", boardDesc]
    $(widgetFile "board")
    
postBoardR :: Text -> Int -> Handler Html
postBoardR board _ = do
  muser    <- maybeAuth
  mgroup   <- getMaybeGroup muser
  boardVal <- getBoardVal404 board
  checkViewAccess mgroup boardVal
  -------------------------------------------------------------------------------------------------------   
  let msgRedirect msg  = setMessageI msg >> redirect (BoardNoPageR board)
      maxMessageLength = boardMaxMsgLength  boardVal
      defaultName      = boardDefaultName   boardVal
      allowedTypes     = boardAllowedTypes  boardVal
      thumbSize        = boardThumbSize     boardVal
      numberFiles      = boardNumberFiles   boardVal
      enableCaptcha    = boardEnableCaptcha boardVal
      opWithoutFile    = boardOpWithoutFile boardVal
  -------------------------------------------------------------------------------------------------------       
  ((result, _),   _) <- runFormPost $ postForm numberFiles
  case result of
    FormFailure _                            -> msgRedirect MsgBadFormData
    FormMissing                              -> msgRedirect MsgNoFormData
    FormSuccess (name, title, message, pswd, captcha, files, goback, Just _)
      | not opWithoutFile   && noFiles files           -> msgRedirect MsgNoFile
      | noMessage message && noFiles files           -> msgRedirect MsgNoFileOrText
      | tooLongMessage message maxMessageLength     -> msgRedirect $ MsgTooLongMessage maxMessageLength
      | not $ all (isFileAllowed allowedTypes) files  -> msgRedirect MsgTypeNotAllowed
      | otherwise                                   -> do
        setSession "message"    (maybe     "" unTextarea message)
        setSession "post-title" (fromMaybe "" title)
        -- check ban
        ip  <- pack <$> getIp
        ban <- runDB $ selectFirst [BanIp ==. ip] [Desc BanId]
        when (isJust ban) $ 
          unlessM (isBanExpired $ fromJust ban) $ do
            setMessageI $ MsgYouAreBanned (banReason $ entityVal $ fromJust ban)
                                          (maybe "never" (pack . myFormatTime) (banExpires $ entityVal $ fromJust ban))
            redirect (BoardNoPageR board)
        -- check captcha
        acaptcha <- lookupSession "acaptcha"
        when (enableCaptcha && isNothing muser) $ do
          when (isNothing acaptcha) $ do
            void $ when (isNothing captcha) (setMessageI MsgWrongCaptcha >> redirect (BoardNoPageR board))
            checkCaptcha (fromJust captcha) (setMessageI MsgWrongCaptcha >> redirect (BoardNoPageR board))
          updateAdaptiveCaptcha acaptcha
        -------------------------------------------------------------------------------------------------------
        now      <- liftIO getCurrentTime
        -- check too fast posting
        lastPost <- runDB $ selectFirst [PostIp ==. ip, PostParent ==. 0] [Desc PostDate] -- last thread by IP
        when (isJust lastPost) $ do
          let diff = ceiling ((realToFrac $ diffUTCTime now (postDate $ entityVal $ fromJust lastPost)) :: Double)
          whenM ((>diff) <$> getConfig configReplyDelay) $ 
            deleteSession "acaptcha" >>
            setMessageI MsgPostingTooFast >> redirect (BoardNoPageR board)
        ------------------------------------------------------------------------------------------------------
        posterId <- getPosterId
        nextId <- maybe 1 ((+1) . postLocalId . entityVal) <$> runDB (selectFirst [PostBoard ==. board] [Desc PostLocalId])
        messageFormatted <- doAwfulMarkup message board 0
        let newPost = Post { postBoard        = board
                           , postLocalId      = nextId
                           , postParent       = 0
                           , postMessage      = messageFormatted
                           , postRawMessage   = maybe "" unTextarea message
                           , postTitle        = maybe ("" :: Text) (T.take 30) title
                           , postName         = maybe defaultName (T.take 10) name
                           , postDate         = now
                           , postPassword     = pswd
                           , postBumped       = Just now
                           , postIp           = ip
                           , postLocked       = False
                           , postSticked      = False
                           , postAutosage     = False
                           , postDeleted      = False
                           , postDeletedByOp  = False
                           , postOwner        = pack . show . userGroup . entityVal <$> muser
                           , postPosterId     = posterId
                           , postLastModified = Nothing
                           }
        void $ insertFiles files thumbSize =<< runDB (insert newPost)
        -- delete old threads
        let tl = boardThreadLimit boardVal
          in when (tl >= 0) $
               flip deletePosts False =<< runDB (selectList [PostBoard ==. board, PostParent ==. 0] [Desc PostBumped, OffsetBy tl])
        -------------------------------------------------------------------------------------------------------
        when (isJust name) $ setSession "name" (fromMaybe defaultName name) 
        deleteSession "message"
        deleteSession "post-title"
        case goback of
          ToBoard  -> setSession "goback" "ToBoard"  >> redirect (BoardNoPageR board )
          ToThread -> setSession "goback" "ToThread" >> redirect (ThreadR      board nextId)
    _  -> msgRedirect MsgUnknownError
