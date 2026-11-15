{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Named patterns (@__pattern P(a, b) = body@) and named shared paths
-- (@__path P = A / B.C@): their rules, and their expansion. Every use of a
-- pattern is replaced by its body, each parameter by its argument, and
-- every use of a path, in a transition's shared paths, by its segments,
-- before the spec is checked; the checker then sees only ordinary
-- patterns and paths.
--
-- A name copied from a body keeps its line and column there, and its
-- position's file name is replaced by a tag for the use it was copied
-- for ('patternOrigin'), so an error found in it can be reported at the
-- use, with a pointer into the body.
module SumSpec.Expand
  ( Expansion (..)
  , Origin (..)
  , expandSpec
  , expandPatternIn
  , pathDefs
  , patternDefs
  , patternOrigin
  ) where

import Control.Monad.Trans.State.Strict (State, gets, modify', runState)
import Data.Graph (SCC (..), stronglyConnComp)
import Data.List.NonEmpty (NonEmpty (..))
import Data.List.NonEmpty qualified as NE
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as M
import Data.Set (Set)
import Data.Set qualified as S
import Data.Text (Text)
import Data.Text qualified as T
import SumSpec.Syntax
import Text.Megaparsec (SourcePos (..), unPos)
import Text.Read (readMaybe)

-- | A spec with every use of a pattern expanded, the errors found on the
-- way, and where each use is.
data Expansion = Expansion
  { expansionSpec :: Spec
  , expansionErrors :: [(SourcePos, Text)]
  -- ^ The errors in the definitions of patterns and in their uses. An
  -- error found inside a body is at a tagged position (see
  -- 'patternOrigin').
  , expansionUses :: Map Int SourcePos
  -- ^ Each use, by the number in its tag: the position of its name.
  }

-- | Where a position copied from a body comes from: the use it was copied
-- for, the pattern or path whose body holds it (@pattern P@, @path P@),
-- and its place in that body.
data Origin = Origin
  { originUse :: SourcePos
  , originDefinition :: Text
  , originBody :: SourcePos
  }

-- | The origin of a position, when it was copied from a body.
patternOrigin :: Expansion -> SourcePos -> Maybe Origin
patternOrigin ex pos = do
  (i, name) <- parseTag (sourceName pos)
  use <- M.lookup i (expansionUses ex)
  pure (Origin use name pos {sourceName = sourceName use})

-- | The patterns a spec defines, the first of each name.
patternDefs :: Spec -> Map Text PatternDef
patternDefs spec =
  M.fromListWith
    (\_ old -> old)
    [(nameText (patternDefName d), d) | DefPattern d <- specDefinitions spec]

-- | The paths a spec defines, the first of each name.
pathDefs :: Spec -> Map Text PathDef
pathDefs spec =
  M.fromListWith
    (\_ old -> old)
    [(nameText (pathDefName d), d) | DefPath d <- specDefinitions spec]

-- ---------- Tags ----------

-- | The file name of a position copied from the body of a definition
-- (@pattern P@, @path P@) for the use numbered. It starts with a
-- character no file path holds.
tag :: Int -> Text -> FilePath
tag i label = "\0use " <> show i <> " " <> T.unpack label

parseTag :: FilePath -> Maybe (Int, Text)
parseTag file = case words <$> stripPrefix "\0use " file of
  Just (i : label@(_ : _)) -> (,T.pack (unwords label)) <$> readMaybe i
  _ -> Nothing
  where
    stripPrefix prefix s
      | take (length prefix) s == prefix = Just (drop (length prefix) s)
      | otherwise = Nothing

-- ---------- Expansion ----------

-- | What a use can expand to: the patterns and the paths that can be used,
-- each with whether it is in a cycle.
data Env = Env (Map Text (PatternDef, Bool)) (Map Text (PathDef, Bool))

data St = St
  { stNext :: Int
  , stUses :: Map Int SourcePos
  , stErrors :: [(SourcePos, Text)]
  }

type M = State St

-- | Checks the definitions of patterns and expands every use in the spec:
-- in sources, targets, guards, shared paths, inputs, dispatches and
-- @__init@. A use that can't be expanded is reported and left as
-- written. The definitions stay in the spec, as written.
expandSpec :: Spec -> Expansion
expandSpec spec =
  Expansion
    spec {specDefinitions = defs'}
    (defErrors <> reverse (stErrors st))
    (stUses st)
  where
    (defs', st) = runState (mapM (definition env) (specDefinitions spec)) (St 0 M.empty [])
    (env, defErrors) = prepare spec

-- | A pattern with every use of the spec's patterns in it expanded, for
-- the language server; errors are dropped.
expandPatternIn :: Spec -> Pattern -> Pattern
expandPatternIn spec p = fst (runState (pat env p) (St 0 M.empty []))
  where
    env = fst (prepare spec)

-- | The patterns that can be used, and the errors in their definitions. A
-- pattern with the name of a type or a constant isn't one: the name is
-- the type's.
prepare :: Spec -> (Env, [(SourcePos, Text)])
prepare spec = (Env usable usablePaths, errors <> pathErrors)
  where
    defs = [d | DefPattern d <- specDefinitions spec]
    taken =
      M.fromList $
        [(nameText (atomicName a), "a type") | a <- specAtomics spec]
          <> [(nameText (typeDefName t), "a type") | DefType t <- specDefinitions spec]
          <> [(nameText (constName c), "a constant") | DefConst c <- specDefinitions spec]
    known = M.filterWithKey (\k _ -> M.notMember k taken) (patternDefs spec)
    cyclic = cycles (uses . patternDefBody) known
    usable = M.mapWithKey (\k d -> (d, k `S.member` cyclic)) known
    -- Paths: a name new to the spec, patterns included.
    pathList = [d | DefPath d <- specDefinitions spec]
    pathTaken = taken <> M.map (const "a pattern") (patternDefs spec)
    knownPaths = M.filterWithKey (\k _ -> M.notMember k pathTaken) (pathDefs spec)
    cyclicPaths = cycles pathUses knownPaths
    usablePaths = M.mapWithKey (\k d -> (d, k `S.member` cyclicPaths)) knownPaths
    pathErrors =
      [ ( namePos n
        , "path " <> nameText n <> " is defined twice (first on line " <> lineOf first <> ")"
        )
      | (i, d) <- zip [0 :: Int ..] pathList
      , let n = pathDefName d
      , first : _ <-
          [[pathDefName f | f <- take i pathList, nameText (pathDefName f) == nameText n]]
      ]
        <> [ ( namePos n
             , "path "
                 <> nameText n
                 <> " has the name of "
                 <> what
                 <> "; a path's name is new to the spec"
             )
           | d <- pathList
           , let n = pathDefName d
           , Just what <- [M.lookup (nameText n) pathTaken]
           ]
        <> [ ( namePos n
             , "path " <> nameText n <> " uses itself; a path may use another, but not in a cycle"
             )
           | d <- M.elems knownPaths
           , let n = pathDefName d
           , nameText n `S.member` cyclicPaths
           ]
    lineOf n = T.pack (show (unPos (sourceLine (namePos n))))
    errors =
      concat
        [ [ ( namePos n
            , "pattern "
                <> nameText n
                <> " is defined twice (first on line "
                <> line first
                <> ")"
            )
          | (d, first) <- repeats defs
          , let n = patternDefName d
          ]
        , [ ( namePos n
            , "pattern "
                <> nameText n
                <> " has the name of "
                <> what
                <> "; a pattern's name is new to the spec"
            )
          | d <- defs
          , let n = patternDefName d
          , Just what <- [M.lookup (nameText n) taken]
          ]
        , [ ( namePos n
            , "pattern "
                <> nameText n
                <> " uses itself"
                <> through n
                <> "; a pattern may use another, but not in a cycle"
            )
          | d <- M.elems known
          , let n = patternDefName d
          , nameText n `S.member` cyclic
          ]
        , concatMap bodyErrors defs
        ]
    line first = T.pack (show (unPos (sourceLine (namePos (patternDefName first)))))
    repeats ds =
      [ (d, first)
      | (i, d) <- zip [0 :: Int ..] ds
      , first : _ <-
          [[f | f <- take i ds, nameText (patternDefName f) == nameText (patternDefName d)]]
      ]
    through n = case [ u
                     | u <- uses (patternDefBody (known M.! nameText n))
                     , u /= nameText n
                     , u `S.member` cyclic
                     ] of
      [] -> ""
      us -> ", through " <> T.intercalate ", " us

-- | The names of the definitions in a cycle, given the names each uses.
cycles :: (d -> [Text]) -> Map Text d -> Set Text
cycles usesOf known =
  S.fromList . concat $
    [ case scc of
        CyclicSCC ns -> ns
        AcyclicSCC n
          | n `elem` usesOf (known M.! n) -> [n]
          | otherwise -> []
    | scc <-
        stronglyConnComp
          [ (k, k, filter (`M.member` known) (usesOf d))
          | (k, d) <- M.toList known
          ]
    ]

-- | The segments of a path that may be paths: those of one name.
pathUses :: PathDef -> [Text]
pathUses d = [nameText n | n :| [] <- NE.toList (pathDefBody d)]

-- | The names at the head of a pattern and of its arguments: the patterns
-- it may use. The paths of alternatives are variants.
uses :: Pattern -> [Text]
uses = \case
  PatternPath (h :| _) args -> nameText h : concatMap uses args
  PatternApply (h :| _) groups -> nameText h : concatMap (concatMap uses) groups
  PatternElement (h :| _) _ args -> nameText h : concatMap uses args
  PatternAlts (h :| _) alts -> nameText h : concatMap altUses alts
  PatternNamed p _ -> uses p
  PatternPrimed _ p -> uses p
  _ -> []
  where
    altUses = \case
      PatternPath _ args -> concatMap uses args
      PatternApply _ groups -> concatMap (concatMap uses) groups
      PatternAlts _ alts -> concatMap altUses alts
      p -> uses p

-- | A body names nothing, uses only its parameters, and each of them, a
-- parameter standing for a whole argument or the key of an element path.
bodyErrors :: PatternDef -> [(SourcePos, Text)]
bodyErrors (PatternDef name params body) =
  [ (namePos p, "parameter " <> nameText p <> " is written twice")
  | (i, p) <- zip [0 :: Int ..] params
  , any ((== nameText p) . nameText) (take i params)
  ]
    <> [ ( namePos p
         , "parameter "
             <> nameText p
             <> " is not used in the body of "
             <> nameText name
         )
       | p <- params
       , nameText p `notElem` map nameText (bodyNames body)
       ]
    <> go True body
  where
    isParam n = nameText n `elem` map nameText params
    free n =
      ( namePos n
      , nameText n
          <> " is not a parameter of "
          <> nameText name
          <> "; a pattern's body uses only its parameters"
      )
    naming n =
      ( namePos n
      , "a pattern's body names no value; name it at the use, as an argument"
      )
    whole n =
      ( namePos n
      , "parameter "
          <> nameText n
          <> " stands for a whole argument; write the prime or the name at the use"
      )
    go top = \case
      PatternPath _ args -> concatMap (go False) args
      PatternApply _ groups -> concatMap (concatMap (go False)) groups
      PatternElement _ key args -> keyErrors key <> concatMap (go False) args
      PatternAlts _ alts -> concatMap (go top) alts
      PatternName n
        | isParam n -> []
        | otherwise -> [free n]
      PatternNamed (PatternName p) _ | isParam p -> [whole p]
      PatternNamed p n -> naming n : go top p
      PatternBound n -> [naming n]
      PatternPrimed _ (PatternName p) | isParam p -> [whole p]
      PatternPrimed _ p -> go top p
      PatternExpr e ->
        [ if isParam n
            then
              ( namePos n
              , "parameter "
                  <> nameText n
                  <> " stands for a whole argument, not a value inside a computed one"
              )
            else free n
        | n <- exprNames e
        ]
      PatternList {} -> []
    keyErrors = \case
      KeyOne x
        | isParam x -> []
        | otherwise -> [free x]
      KeyEach _ binder xs ->
        [naming b | Just b <- [binder]]
          <> [free x | Just x <- [xs], not (isParam x)]

-- | Every lowercase name in a pattern: in arguments, element keys and
-- computed values.
bodyNames :: Pattern -> [Name]
bodyNames = \case
  PatternPath _ args -> concatMap bodyNames args
  PatternApply _ groups -> concatMap (concatMap bodyNames) groups
  PatternElement _ key args -> keyNames key <> concatMap bodyNames args
  PatternAlts _ alts -> concatMap bodyNames alts
  PatternName n -> [n]
  PatternNamed p _ -> bodyNames p
  PatternPrimed _ p -> bodyNames p
  PatternExpr e -> exprNames e
  PatternBound _ -> []
  PatternList {} -> []
  where
    keyNames = \case
      KeyOne x -> [x]
      KeyEach _ _ xs -> maybe [] pure xs

exprNames :: Expr -> [Name]
exprNames = \case
  ExprName n -> [n]
  ExprBin _ _ a b -> exprNames a <> exprNames b
  _ -> []

report :: Name -> Text -> M ()
report n message = modify' (\s -> s {stErrors = (namePos n, message) : stErrors s})

definition :: Env -> Definition -> M Definition
definition env = \case
  DefInit k p -> DefInit k <$> pat env p
  DefEvent (Event n input transitions) ->
    fmap DefEvent $
      Event n <$> traverse (pat env) input <*> traverse (transition env) transitions
  d -> pure d

transition :: Env -> Transition -> M Transition
transition env (Transition paths branches) =
  Transition . concat <$> mapM (shared env) paths <*> traverse (branch env) branches

branch :: Env -> Branch -> M Branch
branch env (Branch from g to notes d) =
  Branch
    <$> traverse (pat env) from
    <*> traverse (guard env) g
    <*> traverse (pat env) to
    <*> pure notes
    <*> traverse (\(Dispatch e args) -> Dispatch e <$> mapM (pat env) args) d

guard :: Env -> Guard -> M Guard
guard env = \case
  GuardPattern p -> GuardPattern <$> pat env p
  GuardNot g -> GuardNot <$> guard env g
  GuardAnd gs -> GuardAnd <$> traverse (guard env) gs
  GuardOr gs -> GuardOr <$> traverse (guard env) gs
  g -> pure g

-- | A shared path that is a named path stands for its segments, the first
-- one standing where the name is. A pattern isn't a shared path.
shared :: Env -> Shared -> M [Shared]
shared env@(Env pats paths) s@(Shared (h :| rest) key) =
  case M.lookup (nameText h) paths of
    Just (d, isCyclic)
      | not (null rest) -> [s] <$ report h (afterDot "path" h)
      | Just _ <- key -> [s] <$ report h ("path " <> nameText h <> " takes no element key")
      | isCyclic -> [s] <$ report h (cannotExpand "path" h)
      | otherwise -> do
          i <- useTag h
          let
            label = "path " <> nameText (pathDefName d)
            copy = fmap (\(Name pos t) -> Name pos {sourceName = tag i label} t)
            segments = [Shared (copy seg) Nothing | seg <- NE.toList (pathDefBody d)]
          expanded <- concat <$> mapM (shared env) segments
          pure $ case expanded of
            Shared ns k : more -> Shared (atUse h ns) k : more
            [] -> []
    Nothing
      | M.member (nameText h) pats ->
          [s]
            <$ report
              h
              ( nameText h
                  <> " is a pattern, which goes where a pattern goes; "
                  <> "a shared path is written with paths or a __path"
              )
      | otherwise -> pure [s]

-- | A pattern with every use in it expanded.
pat :: Env -> Pattern -> M Pattern
pat env@(Env defs paths) = \case
  p
    | h : _ <- headNames p
    , M.member (nameText h) paths -> do
        report h (nameText h <> " is a path, which goes before =>, not where a pattern goes")
        pure p
  PatternPath ns@(h :| rest) args
    | Just found <- M.lookup (nameText h) defs ->
        if null rest
          then useOf env h found (if null args then [] else [args])
          else PatternPath ns <$> mapM (pat env) args <* report h (afterDot "pattern" h)
    | otherwise -> PatternPath ns <$> mapM (pat env) args
  PatternApply ns@(h :| rest) groups
    | Just found <- M.lookup (nameText h) defs
    , null rest ->
        useOf env h found (NE.toList groups)
    | otherwise -> do
        report
          h
          ( "a comma separates the arguments of a named pattern; "
              <> "join the arguments of a type with \"*\""
          )
        PatternPath ns <$> mapM (pat env) (concat groups)
  PatternElement ns@(h :| _) key args -> do
    case M.lookup (nameText h) defs of
      Just _ -> report h (keyed h)
      Nothing -> pure ()
    PatternElement ns key <$> mapM (pat env) args
  PatternAlts ns@(h :| _) alts -> do
    case M.lookup (nameText h) defs of
      Just _ -> report h (afterDot "pattern" h)
      Nothing -> pure ()
    PatternAlts ns <$> traverse alt alts
  PatternNamed p n -> (`PatternNamed` n) <$> pat env p
  PatternPrimed pos p -> PatternPrimed pos <$> pat env p
  p -> pure p
  where
    -- An alternative is written from its sum: its path is variants.
    alt = \case
      PatternPath ns args -> PatternPath ns <$> mapM (pat env) args
      PatternApply ns@(h :| _) groups -> do
        report h "a comma separates the arguments of a named pattern, not of a variant"
        PatternPath ns <$> mapM (pat env) (concat groups)
      PatternAlts ns alts -> PatternAlts ns <$> traverse alt alts
      p -> pat env p

-- | The head of a pattern that may name a pattern or a path.
headNames :: Pattern -> [Name]
headNames = \case
  PatternPath (h :| _) _ -> [h]
  PatternApply (h :| _) _ -> [h]
  PatternElement (h :| _) _ _ -> [h]
  PatternAlts (h :| _) _ -> [h]
  _ -> []

-- | A use of a pattern, with its groups of arguments: the body, each
-- parameter replaced by its group, and the uses in it expanded.
useOf :: Env -> Name -> (PatternDef, Bool) -> [[Pattern]] -> M Pattern
useOf env h (d, isCyclic) groups = do
  groups' <- mapM (mapM (pat env)) groups
  let
    asWritten = PatternPath (h :| []) (concat groups')
    params = patternDefParams d
  case () of
    _
      | isCyclic -> asWritten <$ report h (cannotExpand "pattern" h)
      | length groups' /= length params -> do
          report h (arity (length params) (length groups'))
          pure asWritten
      | otherwise -> do
          body <- copyBody h d
          let (expanded, errors) = substitute (M.fromList (zip (map nameText params) groups')) body
          mapM_ (\(n, message) -> report n message) errors
          withHead (atUse h) <$> pat env expanded
  where
    arity want got =
      "pattern "
        <> nameText h
        <> " takes "
        <> count want
        <> ", but "
        <> (if got == 0 then "none is" else count got <> (if got == 1 then " is" else " are"))
        <> " given"
        <> (if want > 1 then "; separate them with commas" else "")
    count k =
      T.pack (show k) <> if k == 1 then " argument" else " arguments"

-- | The head of an expansion stands where the pattern's name is: a
-- message that names the transition by its line names the use's.
atUse :: Name -> NonEmpty Name -> NonEmpty Name
atUse h (Name _ t :| rest) = Name (namePos h) t :| rest

withHead :: (NonEmpty Name -> NonEmpty Name) -> Pattern -> Pattern
withHead f = \case
  PatternPath ns args -> PatternPath (f ns) args
  PatternApply ns groups -> PatternApply (f ns) groups
  PatternElement ns k args -> PatternElement (f ns) k args
  PatternAlts ns alts -> PatternAlts (f ns) alts
  p -> p

-- | The body of a pattern, its positions tagged with the use at this
-- name: a new use, or, for a use inside a body, the use it was copied
-- for.
copyBody :: Name -> PatternDef -> M Pattern
copyBody h d = do
  i <- useTag h
  let file = tag i ("pattern " <> nameText (patternDefName d))
  pure (mapPositions (\p -> p {sourceName = file}) (patternDefBody d))

-- | The number of the use at this name: a new use, or, for a use inside a
-- body, the use it was copied for.
useTag :: Name -> M Int
useTag h = case parseTag (sourceName (namePos h)) of
  Just (i, _) -> pure i
  Nothing -> do
    i <- gets stNext
    modify' (\s -> s {stNext = i + 1, stUses = M.insert i (namePos h) (stUses s)})
    pure i

-- | The body with each parameter replaced by its group of arguments: as an
-- argument, the group is spliced in; as the key of an element path, it is
-- one name. A group that isn't one name there is reported at the key.
substitute :: Map Text [Pattern] -> Pattern -> (Pattern, [(Name, Text)])
substitute groups = go
  where
    go = \case
      PatternPath ns args -> PatternPath ns `first` spliced args
      PatternApply ns gs ->
        let results = map spliced (NE.toList gs)
        in  (PatternApply ns (NE.fromList (map fst results)), concatMap snd results)
      PatternElement ns key args ->
        let
          (key', e1) = keyed' key
          (args', e2) = spliced args
        in
          (PatternElement ns key' args', e1 <> e2)
      PatternAlts ns alts ->
        let results = map go (NE.toList alts)
        in  (PatternAlts ns (NE.fromList (map fst results)), concatMap snd results)
      PatternNamed p n -> (`PatternNamed` n) `first` go p
      PatternPrimed pos p -> PatternPrimed pos `first` go p
      p -> (p, [])
    first f (a, e) = (f a, e)
    spliced args =
      let results =
            [ case a of
                PatternName n | Just g <- M.lookup (nameText n) groups -> (g, [])
                _ -> first pure (go a)
            | a <- args
            ]
      in  (concatMap fst results, concatMap snd results)
    keyed' = \case
      KeyOne x -> first KeyOne (keyName' x)
      KeyEach pos b (Just xs) -> first (KeyEach pos b . Just) (keyName' xs)
      k -> (k, [])
    keyName' x = case M.lookup (nameText x) groups of
      Nothing -> (x, [])
      Just [PatternName y] -> (y, [])
      Just _ ->
        ( x
        ,
          [
            ( x
            , "parameter "
                <> nameText x
                <> " is the key of an element path, so its argument is one name"
            )
          ]
        )

-- | Every position in a pattern, changed.
mapPositions :: (SourcePos -> SourcePos) -> Pattern -> Pattern
mapPositions f = go
  where
    go = \case
      PatternPath ns args -> PatternPath (fmap nm ns) (map go args)
      PatternApply ns gs -> PatternApply (fmap nm ns) (fmap (map go) gs)
      PatternElement ns key args -> PatternElement (fmap nm ns) (k key) (map go args)
      PatternList t key -> PatternList (term t) (nm <$> key)
      PatternName n -> PatternName (nm n)
      PatternNamed p n -> PatternNamed (go p) (nm n)
      PatternBound n -> PatternBound (nm n)
      PatternAlts ns alts -> PatternAlts (fmap nm ns) (fmap go alts)
      PatternPrimed pos p -> PatternPrimed (f pos) (go p)
      PatternExpr e -> PatternExpr (expr e)
    nm (Name pos t) = Name (f pos) t
    k = \case
      KeyOne x -> KeyOne (nm x)
      KeyEach pos b xs -> KeyEach (f pos) (nm <$> b) (nm <$> xs)
    term = \case
      TermName n -> TermName (nm n)
      TermList t key -> TermList (term t) (nm <$> key)
    expr = \case
      ExprName n -> ExprName (nm n)
      ExprLit pos l -> ExprLit (f pos) l
      ExprConst c -> ExprConst (nm c)
      ExprBin op pos a b -> ExprBin op (f pos) (expr a) (expr b)

afterDot :: Text -> Name -> Text
afterDot kind h =
  kind
    <> " "
    <> nameText h
    <> " is a whole "
    <> kind
    <> ": nothing follows it after a dot"

keyed :: Name -> Text
keyed h = "pattern " <> nameText h <> " is a whole pattern, so it takes no element key"

cannotExpand :: Text -> Name -> Text
cannotExpand kind h = kind <> " " <> nameText h <> " uses itself, so it can't be expanded"
