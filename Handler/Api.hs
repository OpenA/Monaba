{-# LANGUAGE TupleSections, OverloadedStrings, ExistentialQuantification #-}
module Handler.Api where

import           Import
import           Yesod.Auth
--------------------------------------------------------------------------------------------------------- 
getPostsHelper :: YesodDB App [Entity Post] -> -- ^ Post selector: selectList [...] [...]
                 YesodDB App [Entity Post] -> -- ^ Post selector: selectList [...] [...]
                 Text -> -- ^ Board name
                 Int  -> -- ^ Thread internal ID
                 Text -> -- ^ Error string
                 HandlerT App IO TypedContent
getPostsHelper selectPostsAll selectPostsHB board thread errorString = do
  muser    <- maybeAuth
  mgroup   <- getMaybeGroup muser
  boardVal <- getBoardVal404 board
  checkViewAccess mgroup boardVal
  let permissions  = getPermissions   mgroup
      geoIpEnabled = boardEnableGeoIp boardVal
      selectPosts  = if HellBanP `elem` permissions then selectPostsAll else selectPostsHB
      selectFiles p = runDB $ selectList [AttachedfileParentId ==. entityKey p] []
  postsAndFiles <- reverse <$> runDB selectPosts >>= mapM (\p -> do
    files <- selectFiles p
    return (p, files))
  t <- runDB $ count [PostBoard ==. board, PostLocalId ==. thread, PostParent ==. 0, PostDeleted ==. False]
  geoIps   <- getCountries (if geoIpEnabled then postsAndFiles else [])
  timeZone <- getTimeZone
  rating   <- getCensorshipRating
  case () of
    _ | t == 0              -> selectRep $ do
          provideRep  $ bareLayout [whamlet|No such thread|]
          provideJson $ object [("error", toJSON ("No such thread"::Text))]
      | null postsAndFiles -> selectRep $ do
          provideRep  $ bareLayout [whamlet|#{errorString}|]
          provideJson $ object [("error", toJSON errorString)]
      | otherwise          -> selectRep $ do
          provideRep  $ bareLayout [whamlet|
                               $forall (post, files) <- postsAndFiles
                                   ^{replyPostWidget muser post files rating True True False permissions geoIps timeZone}
                               |]
          provideJson $ map (entityVal *** map entityVal) postsAndFiles

getApiDeletedPostsR :: Text -> Int -> Handler TypedContent
getApiDeletedPostsR board thread = do
  posterId <- getPosterId
  let selectPostsAll = selectList [PostDeletedByOp ==. True, PostBoard ==. board, PostParent ==. thread, PostDeleted ==. False] [Desc PostDate]
      selectPostsHB  = selectList ( [PostDeletedByOp ==. True, PostBoard ==. board, PostParent ==. thread
                                    ,PostDeleted ==. False, PostHellbanned ==. False] ||.
                                    [PostDeletedByOp ==. True, PostBoard ==. board, PostParent ==. thread
                                    ,PostDeleted ==. False, PostHellbanned ==. True, PostPosterId ==. posterId]
                                  ) [Desc PostDate]
      errorString = "No such posts"
  getPostsHelper selectPostsAll selectPostsHB board thread errorString


getApiAllPostsR :: Text -> Int -> Handler TypedContent
getApiAllPostsR board thread = do
  posterId <- getPosterId
  let selectPostsAll = selectList [PostDeletedByOp ==. False, PostBoard ==. board,
                                   PostParent ==. thread, PostDeleted ==. False] [Desc PostDate]
      selectPostsHB  = selectList ( [PostDeletedByOp ==. False, PostBoard ==. board,
                                     PostParent ==. thread, PostDeleted ==. False, PostHellbanned ==. False] ||.
                                    [PostDeletedByOp ==. False, PostBoard ==. board,
                                     PostParent ==. thread, PostDeleted ==. False, PostHellbanned ==. True,
                                     PostPosterId ==. posterId]
                                  ) [Desc PostDate]
      errorString = "No posts in this thread"
  getPostsHelper selectPostsAll selectPostsHB board thread errorString

getApiNewPostsR :: Text -> Int -> Int -> Handler TypedContent
getApiNewPostsR board thread postId = do
  posterId <- getPosterId
  let selectPostsAll = selectList [PostDeletedByOp ==. False, PostBoard ==. board
                                  ,PostParent ==. thread, PostLocalId >. postId, PostDeleted ==. False] [Desc PostDate]
      selectPostsHB  = selectList ( [PostDeletedByOp ==. False, PostBoard ==. board
                                    ,PostParent ==. thread, PostLocalId >. postId, PostDeleted ==. False, PostHellbanned ==. False] ||.
                                    [PostDeletedByOp ==. False, PostBoard ==. board
                                    ,PostParent ==. thread, PostLocalId >. postId, PostDeleted ==. False, PostHellbanned ==. True
                                    ,PostPosterId ==. posterId]
                                  ) [Desc PostDate]
      errorString = "No new posts"
  getPostsHelper selectPostsAll selectPostsHB board thread errorString

getApiLastPostsR :: Text -> Int -> Int -> Handler TypedContent
getApiLastPostsR board thread postCount = do
  posterId <- getPosterId
  let selectPostsAll = selectList [PostDeletedByOp ==. False, PostBoard ==. board
                                  ,PostParent ==. thread, PostDeleted ==. False] [Desc PostDate, LimitTo postCount]
      selectPostsHB  = selectList ( [PostDeletedByOp ==. False, PostBoard ==. board
                                    ,PostParent ==. thread, PostDeleted ==. False, PostHellbanned ==. False] ||.
                                    [PostDeletedByOp ==. False, PostBoard ==. board
                                    ,PostParent ==. thread, PostDeleted ==. False, PostHellbanned ==. True, PostPosterId ==. posterId]
                                  ) [Desc PostDate, LimitTo postCount]
      errorString = "No such posts"
  getPostsHelper selectPostsAll selectPostsHB board thread errorString

---------------------------------------------------------------------------------------------------------
getApiPostR :: Text -> Int -> Handler TypedContent
getApiPostR board postId = do
  muser    <- maybeAuth
  mgroup   <- getMaybeGroup muser
  boardVal <- getBoardVal404 board
  posterId <- getPosterId
  checkViewAccess mgroup boardVal
  let permissions  = getPermissions   mgroup
      geoIpEnabled = boardEnableGeoIp boardVal
      selectPosts    = if HellBanP `elem` permissions then selectPostsAll else selectPostsHB
      selectPostsAll = [PostBoard ==. board, PostLocalId ==. postId, PostDeleted ==. False]
      selectPostsHB  = [PostBoard ==. board, PostLocalId ==. postId, PostDeleted ==. False, PostHellbanned ==. False] ||.
                       [PostBoard ==. board, PostLocalId ==. postId, PostDeleted ==. False, PostHellbanned ==. True, PostPosterId ==. posterId]
  maybePost <- runDB $ selectFirst selectPosts []
  when (isNothing maybePost) notFound
  let post    = fromJust maybePost
      postKey = entityKey $ fromJust maybePost
  files  <- runDB $ selectList [AttachedfileParentId ==. postKey] []
  geoIps <- getCountries [(post, files) | geoIpEnabled]
  timeZone <- getTimeZone
  rating   <- getCensorshipRating
  let postAndFiles = (entityVal post, map entityVal files)
      widget       = if postParent (entityVal $ fromJust maybePost) == 0
                       then opPostWidget muser post files rating False True permissions geoIps timeZone
                       else replyPostWidget muser post files rating False True False permissions geoIps timeZone
  selectRep $ do
    provideRep $ bareLayout widget
    provideJson postAndFiles
