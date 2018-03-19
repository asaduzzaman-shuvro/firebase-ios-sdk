/*
 * Copyright 2017 Google
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import "Firestore/Source/Model/FSTDocumentSet.h"

#include <map>
#include <set>
#include <utility>

#import "Firestore/Source/Model/FSTDocument.h"
#import "Firestore/third_party/Immutable/FSTImmutableSortedSet.h"

#include "Firestore/core/src/firebase/firestore/model/document_key.h"

using firebase::firestore::model::DocumentKey;

NS_ASSUME_NONNULL_BEGIN

/**
 * The type of the index of the documents in an FSTDocumentSet.
 * @see FSTDocumentSet#index
 */
typedef std::map<DocumentKey, FSTDocument *> IndexType;

/**
 * The type of the main collection of documents in an FSTDocumentSet.
 * @see FSTDocumentSet#sortedSet
 */
typedef FSTImmutableSortedSet<FSTDocument *> SetType;

@interface FSTDocumentSet ()

- (instancetype)initWithIndex:(IndexType)index set:(SetType *)sortedSet NS_DESIGNATED_INITIALIZER;

/**
 * The main collection of documents in the FSTDocumentSet. The documents are ordered by a
 * comparator supplied from a query. The SetType collection exists in addition to the index to
 * allow ordered traversal of the FSTDocumentSet.
 */
@property(nonatomic, strong, readonly) SetType *sortedSet;

@end

@implementation FSTDocumentSet {
  /**
   * An index of the documents in the FSTDocumentSet, indexed by document key. The index
   * exists to guarantee the uniqueness of document keys in the set and to allow lookup and removal
   * of documents by key.
   */
  IndexType _index;
}

+ (instancetype)documentSetWithComparator:(NSComparator)comparator {
  IndexType index{};
  SetType *set = [FSTImmutableSortedSet setWithComparator:comparator];
  return [[FSTDocumentSet alloc] initWithIndex:index set:set];
}

- (instancetype)initWithIndex:(IndexType)index set:(SetType *)sortedSet {
  self = [super init];
  if (self) {
    _index = std::move(index);
    _sortedSet = sortedSet;
  }
  return self;
}

- (BOOL)isEqual:(id)other {
  if (other == self) {
    return YES;
  }
  if (![other isMemberOfClass:[FSTDocumentSet class]]) {
    return NO;
  }

  FSTDocumentSet *otherSet = (FSTDocumentSet *)other;
  if ([self count] != [otherSet count]) {
    return NO;
  }

  NSEnumerator<FSTDocument *> *selfIter = [self.sortedSet objectEnumerator];
  NSEnumerator<FSTDocument *> *otherIter = [otherSet.sortedSet objectEnumerator];

  FSTDocument *selfDoc = [selfIter nextObject];
  FSTDocument *otherDoc = [otherIter nextObject];
  while (selfDoc) {
    if (![selfDoc isEqual:otherDoc]) {
      return NO;
    }
    selfDoc = [selfIter nextObject];
    otherDoc = [otherIter nextObject];
  }
  return YES;
}

- (NSUInteger)hash {
  NSUInteger hash = 0;
  for (FSTDocument *doc in self.sortedSet.objectEnumerator) {
    hash = 31 * hash + [doc hash];
  }
  return hash;
}

- (NSString *)description {
  return [self.sortedSet description];
}

- (NSUInteger)count {
  return _index.size();
}

- (BOOL)isEmpty {
  return _index.empty();
}

- (BOOL)containsKey:(const DocumentKey &)key {
  return _index.find(key) != _index.end();
}

- (FSTDocument *_Nullable)documentForKey:(const DocumentKey &)key {
  return _index[key];
}

- (FSTDocument *_Nullable)firstDocument {
  return [self.sortedSet firstObject];
}

- (FSTDocument *_Nullable)lastDocument {
  return [self.sortedSet lastObject];
}

- (NSUInteger)indexOfKey:(const DocumentKey &)key {
  FSTDocument *doc = _index[key];
  return doc ? [self.sortedSet indexOfObject:doc] : NSNotFound;
}

- (NSEnumerator<FSTDocument *> *)documentEnumerator {
  return [self.sortedSet objectEnumerator];
}

- (NSArray *)arrayValue {
  NSMutableArray<FSTDocument *> *result = [NSMutableArray arrayWithCapacity:self.count];
  for (FSTDocument *doc in self.documentEnumerator) {
    [result addObject:doc];
  }
  return result;
}

- (instancetype)documentSetByAddingDocument:(FSTDocument *_Nullable)document {
  // TODO(mcg): look into making document nonnull.
  if (!document) {
    return self;
  }

  // Remove any prior mapping of the document's key before adding, preventing sortedSet from
  // accumulating values that aren't in the index.
  FSTDocumentSet *removed = [self documentSetByRemovingKey:document.key];

  IndexType index = removed->_index;
  index[document.key] = document;
  SetType *set = [removed.sortedSet setByAddingObject:document];
  return [[FSTDocumentSet alloc] initWithIndex:index set:set];
}

- (instancetype)documentSetByRemovingKey:(const DocumentKey &)key {
  const auto iter = _index.find(key);
  if (iter == _index.end()) {
    return self;
  }

  FSTDocument *doc = iter->second;
  IndexType index = _index;
  index.erase(key);
  SetType *set = [self.sortedSet setByRemovingObject:doc];
  return [[FSTDocumentSet alloc] initWithIndex:index set:set];
}

@end

NS_ASSUME_NONNULL_END
