-- | This module defines a type of _lazy_ linked lists, and associated helper
-- | functions and type class instances.
-- | 
-- | _Note_: Depending on your use-case, you may prefer to use
-- | `Data.Sequence` instead, which might give better performance for certain
-- | use cases. This module is an improvement over `Data.Array` when working with 
-- | immutable lists of data in a purely-functional setting, but does not have 
-- | good random-access performance.

module Data.List.Lazy
  ( List(..)
  , runList
  , Step(..)
  , step
  , nil
  , cons
  , (:)
  , singleton
  , fromList
  , toList
  , repeat
  , iterate
  , cycle
  , unfold
  , index
  , (!!)
  , drop
  , dropWhile
  , take
  , takeWhile
  , length
  , filter
  , mapMaybe
  , catMaybes
  , head
  , tail
  , last
  , init
  , zipWith
  , zip
  , concat
  , concatMap
  , null
  , span
  , group
  , groupBy
  , (\\)
  , insert
  , insertBy
  , insertAt
  , delete
  , deleteBy
  , deleteAt
  , updateAt
  , modifyAt
  , alterAt
  , reverse
  , nub
  , nubBy
  , intersect
  , intersectBy
  , uncons
  , union
  , unionBy
  ) where

import Prelude hiding (cons, (:))

import Data.Lazy

import Data.Maybe
import Data.Tuple (Tuple(..), fst, snd)
import Data.Monoid
import Data.Foldable
import Data.Unfoldable
import Data.Traversable

import Control.Alt
import Control.Plus
import Control.Lazy (Lazy, fix)
import Control.Alternative
import Control.MonadPlus

-- | A lazy linked list.
newtype List a = List (Lazy (Step a))

-- | Unwrap a lazy linked list
runList :: forall a. List a -> Lazy (Step a)
runList (List l) = l

-- | Unwrap a lazy linked list
step :: forall a. List a -> Step a
step = force <<< runList

fromStep :: forall a. Step a -> List a
fromStep = List <<< pure

-- | A list is either empty (represented by the `Nil` constructor) or non-empty, in
-- | which case it consists of a head element, and another list (represented by the 
-- | `Cons` constructor).
data Step a = Nil | Cons a (List a)

-- | The empty list.
-- |
-- | Running time: `O(1)`
nil :: forall a. List a
nil = List $ defer \_ -> Nil

-- | Attach an element to the front of a lazy list.
-- |
-- | Running time: `O(1)`
cons :: forall a. a -> List a -> List a
cons x xs = List $ defer \_ -> Cons x xs

-- | Construct a list from a foldable structure.
-- |
-- | Running time: `O(n)`
toList :: forall f a. (Foldable f) => f a -> List a
toList = foldr cons nil

-- | Convert a list into any unfoldable structure.
-- |
-- | Running time: `O(n)`
fromList :: forall f a. (Unfoldable f) => List a -> [a]
fromList = unfoldr uncons

-- | Create a list by repeating an element
repeat :: forall a. a -> List a
repeat x = fix \xs -> cons x xs

-- | Create a list by iterating a function
iterate :: forall a. (a -> a) -> a -> List a
iterate f x = fix \xs -> cons x (f <$> xs)

-- | Create a list by repeating another list
cycle :: forall a. List a -> List a
cycle xs = fix \ys -> xs <> ys

-- | Unfold a list using a generating function
unfold :: forall a b. (b -> Maybe (Tuple a b)) -> b -> List a
unfold f b = Control.Lazy.defer \_ -> go (f b)
  where
  go Nothing = nil
  go (Just (Tuple a b)) = a : Control.Lazy.defer \_ -> go (f b)

infixr 6 :

-- | An infix alias for `cons`; attaches an element to the front of 
-- | a list.
-- |
-- | Running time: `O(1)`
(:) :: forall a. a -> List a -> List a
(:) = cons

-- | Create a list with a single element.
-- |
-- | Running time: `O(1)`
singleton :: forall a. a -> List a
singleton a = cons a nil

-- | Break a list into its first element, and the remaining elements,
-- | or `Nothing` if the list is empty.
-- |
-- | Running time: `O(1)`
uncons :: forall a. List a -> Maybe (Tuple a (List a))
uncons xs = case force (runList xs) of 
              Nil -> Nothing
              Cons x xs -> Just (Tuple x xs)

-- | Get the element at the specified index, or `Nothing` if the index is out-of-bounds.
-- |
-- | Running time: `O(n)` where `n` is the required index.
index :: forall a. List a -> Number -> Maybe a
index xs = go (step xs) 
  where 
  go Nil _ = Nothing
  go (Cons a _) 0 = Just a
  go (Cons _ as) i = go (step as) (i - 1)

infix 4 !!

-- | An infix synonym for `index`.
(!!) :: forall a. List a -> Number -> Maybe a
(!!) = index

-- | Drop the specified number of elements from the front of a list.
-- |
-- | Running time: `O(n)` where `n` is the number of elements to drop.
drop :: forall a. Number -> List a -> List a
drop n xs = List (go n <$> runList xs)
  where
  go 0 xs = xs
  go _ Nil = Nil
  go n (Cons x xs) = go (n - 1) (step xs)

-- | Drop those elements from the front of a list which match a predicate.
-- |
-- | Running time (worst case): `O(n)`
dropWhile :: forall a. (a -> Boolean) -> List a -> List a
dropWhile p xs = go (step xs)
  where
  go (Cons x xs) | p x = go (step xs)
  go xs = fromStep xs

-- | Take the specified number of elements from the front of a list.
-- |
-- | Running time: `O(n)` where `n` is the number of elements to take.
take :: forall a. Number -> List a -> List a
take n xs = List (go n <$> runList xs)
  where 
  go :: Number -> Step a -> Step a
  go 0 _ = Nil
  go _ Nil = Nil
  go n (Cons x xs) = Cons x (take (n - 1) xs)

-- | Take those elements from the front of a list which match a predicate.
-- |
-- | Running time (worst case): `O(n)`
takeWhile :: forall a. (a -> Boolean) -> List a -> List a
takeWhile p xs = List (go <$> runList xs)
  where
  go (Cons x xs) | p x = Cons x (takeWhile p xs)
  go _ = Nil

-- | Get the length of a list
-- |
-- | Running time: `O(n)`
length :: forall a. List a -> Number
length xs = go (step xs)
  where
  go Nil = 0
  go (Cons _ xs) = 1 + go (step xs)

-- | Filter a list, keeping the elements which satisfy a predicate function.
-- |
-- | Running time: `O(n)`
filter :: forall a. (a -> Boolean) -> List a -> List a
filter p xs = List (go <$> runList xs)
  where
  go Nil = Nil
  go (Cons x xs) 
    | p x = Cons x (filter p xs)
    | otherwise = go (step xs)

-- | Apply a function to each element in a list, keeping only the results which
-- | contain a value.
-- |
-- | Running time: `O(n)`
mapMaybe :: forall a b. (a -> Maybe b) -> List a -> List b
mapMaybe f xs = List (go <$> runList xs)
  where
  go Nil = Nil
  go (Cons x xs) =
    case f x of
      Nothing -> go (step xs)
      Just y -> Cons y (mapMaybe f xs)

-- | Filter a list of optional values, keeping only the elements which contain
-- | a value.
catMaybes :: forall a. List (Maybe a) -> List a
catMaybes = mapMaybe id

-- | Get the first element in a list, or `Nothing` if the list is empty.
-- |
-- | Running time: `O(1)`.
head :: forall a. List a -> Maybe a
head xs = fst <$> uncons xs

-- | Get all but the first element of a list, or `Nothing` if the list is empty.
-- |
-- | Running time: `O(1)`
tail :: forall a. List a -> Maybe (List a)
tail xs = snd <$> uncons xs

-- | Get the last element in a list, or `Nothing` if the list is empty.
-- |
-- | Running time: `O(n)`.
last :: forall a. List a -> Maybe a
last xs = go (step xs)
  where
  go (Cons x xs) | null xs = Just x
                 | otherwise = go (step xs)
  go _            = Nothing

-- | Get all but the last element of a list, or `Nothing` if the list is empty.
-- |
-- | Running time: `O(n)`
init :: forall a. List a -> Maybe (List a)
init xs = go (step xs)
  where
  go :: Step a -> Maybe (List a)
  go (Cons x xs) | null xs = Just nil
                 | otherwise = cons x <$> go (step xs)
  go _            = Nothing

-- | Apply a function to pairs of elements at the same positions in two lists,
-- | collecting the results in a new list.
-- |
-- | If one list is longer, elements will be discarded from the longer list.
-- |
-- | For example
-- |
-- | ```purescript
-- | zipWith (*) (1 : 2 : 3 : Nil) (4 : 5 : 6 : 7 Nil) == 4 : 10 : 18 : Nil
-- | ```
-- |
-- | Running time: `O(min(m, n))`
zipWith :: forall a b c. (a -> b -> c) -> List a -> List b -> List c
zipWith f xs ys = List (go <$> runList xs <*> runList ys)
  where
  go :: Step a -> Step b -> Step c 
  go Nil _ = Nil
  go _ Nil = Nil
  go (Cons a as) (Cons b bs) = Cons (f a b) (zipWith f as bs)

-- | Collect pairs of elements at the same positions in two lists.
-- |
-- | Running time: `O(min(m, n))`
zip :: forall a b. List a -> List b -> List (Tuple a b)
zip = zipWith Tuple

-- | Flatten a list of lists.
-- |
-- | Running time: `O(n)`, where `n` is the total number of elements.
concat :: forall a. List (List a) -> List a
concat = (>>= id)

-- | Apply a function to each element in a list, and flatten the results
-- | into a single, new list.
-- |
-- | Running time: `O(n)`, where `n` is the total number of elements.
concatMap :: forall a b. (a -> List b) -> List a -> List b
concatMap f xs = List (go <$> runList xs)
  where
  go Nil = Nil
  go (Cons x xs) = step (f x <> concatMap f xs)

-- | Test whether a list is empty.
-- |
-- | Running time: `O(1)`
null :: forall a. List a -> Boolean
null xs = case uncons xs of
            Nothing -> true
            _ -> false
            
-- | Split a list into two parts:
-- |
-- | 1. the longest initial segment for which all elements satisfy the specified predicate
-- | 2. the remaining elements
-- |
-- | For example,
-- |
-- | ```purescript
-- | span (\n -> n % 2 == 1) (1 : 3 : 2 : 4 : 5 : Nil) == Tuple (1 : 3 : Nil) (2 : 4 : 5 : Nil)
-- | ```
-- |
-- | Running time: `O(n)`
span :: forall a. (a -> Boolean) -> List a -> Tuple (List a) (List a)
span p xs = 
  case uncons xs of
    xs@(Just (Tuple x xs')) | p x ->
      case span p xs' of
        Tuple ys zs -> Tuple (cons x ys) zs
    _ -> Tuple nil xs

-- | Group equal, consecutive elements of a list into lists.
-- |
-- | For example,
-- |
-- | ```purescript
-- | group (1 : 1 : 2 : 2 : 1 : Nil) == (1 : 1 : Nil) : (2 : 2 : Nil) : (1 : Nil) : Nil
-- | ```
-- |
-- | Running time: `O(n)`
group :: forall a. (Eq a) => List a -> List (List a)
group = groupBy (==)

-- | Group equal, consecutive elements of a list into lists, using the specified
-- | equivalence relation to determine equality.
-- |
-- | Running time: `O(n)`
groupBy :: forall a. (a -> a -> Boolean) -> List a -> List (List a)
groupBy eq xs = List (go <$> runList xs)
  where
  go Nil = Nil
  go (Cons x xs) = 
    case span (eq x) xs of
      Tuple ys zs -> Cons (cons x ys) (groupBy eq zs)

infix 5 \\

-- | Delete the first occurrence of each element in the second list from the first list.
-- |
-- | Running time: `O(n^2)`
(\\) :: forall a. (Eq a) => List a -> List a -> List a
(\\) = foldl (flip delete)

-- | Insert an element into a sorted list.
-- |
-- | Running time: `O(n)`
insert :: forall a. (Ord a) => a -> List a -> List a
insert = insertBy compare

-- | Insert an element into a sorted list, using the specified function to determine the ordering
-- | of elements.
-- |
-- | Running time: `O(n)`
insertBy :: forall a. (a -> a -> Ordering) -> a -> List a -> List a
insertBy cmp x xs = List (go <$> runList xs)
  where
  go Nil = Cons x nil
  go ys@(Cons y ys') =
    case cmp x y of
      GT -> Cons y (insertBy cmp x ys')
      _  -> Cons x (fromStep ys)

-- | Insert an element into a list at the specified index, returning a new
-- | list or `Nothing` if the index is out-of-bounds.
-- |
-- | This function differs from the strict equivalent in that out-of-bounds arguments
-- | result in the element being appended at the _end_ of the list.
-- |
-- | Running time: `O(n)`
insertAt :: forall a. Number -> a -> List a -> List a
insertAt 0 x xs = cons x xs
insertAt n x xs = List (go <$> runList xs)
  where
  go Nil = Cons x nil
  go (Cons y ys) = Cons y (insertAt (n - 1) x ys)

-- | Delete the first occurrence of an element from a list.
-- |
-- | Running time: `O(n)`
delete :: forall a. (Eq a) => a -> List a -> List a
delete = deleteBy (==)

-- | Delete the first occurrence of an element from a list, using the specified 
-- | function to determine equality of elements.
-- |
-- | Running time: `O(n)`
deleteBy :: forall a. (a -> a -> Boolean) -> a -> List a -> List a
deleteBy eq x xs = List (go <$> runList xs)
  where
  go Nil = Nil
  go (Cons y ys) | eq x y = step ys
                 | otherwise = Cons y (deleteBy eq x ys)

-- | Delete an element from a list at the specified index, returning a new
-- | list or `Nothing` if the index is out-of-bounds.
-- |
-- | This function differs from the strict equivalent in that out-of-bounds arguments
-- | result in the original list being returned unchanged.
-- |
-- | Running time: `O(n)`
deleteAt :: forall a. Number -> List a -> List a
deleteAt n xs = List (go n <$> runList xs)
  where
  go _ Nil = Nil
  go 0 (Cons y ys) = step ys
  go n (Cons y ys) = Cons y (deleteAt (n - 1) ys)

-- | Update the element at the specified index, returning a new
-- | list or `Nothing` if the index is out-of-bounds.
-- |
-- | This function differs from the strict equivalent in that out-of-bounds arguments
-- | result in the original list being returned unchanged.
-- |
-- | Running time: `O(n)`
updateAt :: forall a. Number -> a -> List a -> List a
updateAt n x xs = List (go n <$> runList xs)
  where
  go _ Nil = Nil
  go 0 (Cons _ ys) = Cons x ys
  go n (Cons y ys) = Cons y (deleteAt (n - 1) ys)

-- | Update the element at the specified index by applying a function to
-- | the current value, returning a new list or `Nothing` if the index is 
-- | out-of-bounds.
-- |
-- | This function differs from the strict equivalent in that out-of-bounds arguments
-- | result in the original list being returned unchanged.
-- |
-- | Running time: `O(n)`
modifyAt :: forall a. Number -> (a -> a) -> List a -> List a
modifyAt n f = alterAt n (Just <<< f)

-- | Update or delete the element at the specified index by applying a 
-- | function to the current value, returning a new list or `Nothing` if the 
-- | index is out-of-bounds.
-- |
-- | This function differs from the strict equivalent in that out-of-bounds arguments
-- | result in the original list being returned unchanged.
-- |
-- | Running time: `O(n)`
alterAt :: forall a. Number -> (a -> Maybe a) -> List a -> List a
alterAt n f xs = List (go n <$> runList xs)
  where
  go _ Nil = Nil
  go 0 (Cons y ys) = case f y of
    Nothing -> step ys
    Just y' -> Cons y' ys
  go n (Cons y ys) = Cons y (deleteAt (n - 1) ys)

-- | Reverse a list.
-- |
-- | Running time: `O(n)`
reverse :: forall a. List a -> List a
reverse xs = go nil (step xs)
  where
  go acc Nil = acc
  go acc (Cons x xs) = go (cons x acc) (step xs)

-- | Remove duplicate elements from a list.
-- |
-- | Running time: `O(n^2)`
nub :: forall a. (Eq a) => List a -> List a
nub = nubBy (==)

-- | Remove duplicate elements from a list, using the specified 
-- | function to determine equality of elements.
-- |
-- | Running time: `O(n^2)`
nubBy :: forall a. (a -> a -> Boolean) -> List a -> List a
nubBy eq xs = List (go <$> runList xs)
  where
  go Nil = Nil
  go (Cons x xs) = Cons x (nubBy eq (filter (\y -> not (eq x y)) xs))

-- | Calculate the intersection of two lists.
-- |
-- | Running time: `O(n^2)`
intersect :: forall a. (Eq a) => List a -> List a -> List a
intersect = intersectBy (==)

-- | Calculate the intersection of two lists, using the specified 
-- | function to determine equality of elements.
-- |
-- | Running time: `O(n^2)`
intersectBy :: forall a. (a -> a -> Boolean) -> List a -> List a -> List a
intersectBy eq xs ys = filter (\x -> any (eq x) ys) xs

-- | Calculate the union of two lists.
-- |
-- | Running time: `O(n^2)`
union :: forall a. (Eq a) => List a -> List a -> List a
union = unionBy (==)

-- | Calculate the union of two lists, using the specified 
-- | function to determine equality of elements.
-- |
-- | Running time: `O(n^2)`
unionBy :: forall a. (a -> a -> Boolean) -> List a -> List a -> List a
unionBy eq xs ys = xs <> foldl (flip (deleteBy eq)) (nubBy eq ys) xs

instance showList :: (Show a) => Show (List a) where
  show xs = "fromStrict (" ++ go (step xs) ++ ")"
    where
    go Nil = "Nil"
    go (Cons x xs) = "Cons (" ++ show x ++ ") (" ++ go (step xs) ++ ")"

instance eqList :: (Eq a) => Eq (List a) where
  (==) xs ys = go (step xs) (step ys)
    where
    go Nil Nil = true
    go (Cons x xs) (Cons y ys) 
      | x == y = go (step xs) (step ys)
    go _ _ = false
  (/=) xs ys = not (xs == ys)

instance ordList :: (Ord a) => Ord (List a) where
  compare xs ys = go (step xs) (step ys)
    where
    go Nil Nil = EQ
    go Nil _   = LT
    go _   Nil = GT
    go (Cons x xs) (Cons y ys) = 
      case compare x y of
        EQ -> go (step xs) (step ys)
        other -> other

instance lazyList :: Lazy (List a) where
  defer f = List $ defer (step <<< f)

instance semigroupList :: Semigroup (List a) where
  (<>) xs ys = List (go <$> runList xs)
    where
    go Nil = step ys
    go (Cons x xs) = Cons x (xs <> ys)

instance monoidList :: Monoid (List a) where
  mempty = nil

instance functorList :: Functor List where
  (<$>) f xs = List (go <$> runList xs)
    where
    go Nil = Nil
    go (Cons x xs) = Cons (f x) (f <$> xs)

instance foldableList :: Foldable List where
  -- foldr :: forall a b. (a -> b -> b) -> b -> f a -> b
  foldr o b xs = go (step xs)
    where
    go Nil = b
    go (Cons a as) = a `o` foldr o b as

  -- foldl :: forall a b. (b -> a -> b) -> b -> f a -> b
  foldl o b xs = go (step xs)
    where
    go Nil = b
    go (Cons a as) = foldl o (b `o` a) as

  -- foldMap :: forall a m. (Monoid m) => (a -> m) -> f a -> m 
  foldMap f xs = go (step xs)
    where
    go Nil = mempty
    go (Cons x xs) = f x <> foldMap f xs

instance unfoldableList :: Unfoldable List where
  -- unfoldr :: forall a b. (b -> Maybe (Tuple a b)) -> b -> List a
  unfoldr f b = go (f b)
    where
    go Nothing = nil
    go (Just (Tuple a b)) = cons a (go (f b))

instance traversableList :: Traversable List where
  -- traverse :: forall a b m. (Applicative m) => (a -> m b) -> t a -> m (t b)
  traverse f xs = go (step xs)
    where
    go Nil = pure nil
    go (Cons x xs) = cons <$> f x <*> traverse f xs

  -- sequence :: forall a m. (Applicative m) => t (m a) -> m (t a)   
  sequence xs = go (step xs)
    where
    go Nil = pure nil
    go (Cons x xs) = cons <$> x <*> sequence xs

instance applyList :: Apply List where
  (<*>) = ap

instance applicativeList :: Applicative List where
  pure = singleton

instance bindList :: Bind List where
  (>>=) = flip concatMap

instance monadList :: Monad List

instance altList :: Alt List where
  (<|>) = (<>)

instance plusList :: Plus List where
  empty = nil

instance alternativeList :: Alternative List 

instance monadPlusList :: MonadPlus List