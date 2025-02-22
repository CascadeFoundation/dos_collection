module dos_collection::collection;

use dos_bucket::bucket::Bucket;
use std::string::String;

//=== Aliases ===

public use fun collection_admin_cap_id as CollectionAdminCap.id;
public use fun collection_admin_cap_collection_id as CollectionAdminCap.collection_id;

//=== Structs ===

public struct COLLECTION has drop {}

public struct Collection<phantom T> has key {
    id: UID,
    kind: CollectionKind,
    name: String,
    description: String,
    bucket: Bucket,
}

public struct CollectionAdminCap has key, store {
    id: UID,
    collection_id: ID,
}

public struct ShareCollectionPromise has key {
    id: UID,
    collection_id: ID,
}

public enum CollectionKind has copy, drop, store {
    CAPPED { supply: u64, total_supply: u64 },
    UNCAPPED { supply: u64 },
}

const EInvalidCollectionAdminCap: u64 = 0;

//=== Public Functions ===

public fun new<T>(
    kind: CollectionKind,
    name: String,
    description: String,
    bucket: Bucket,
    ctx: &mut TxContext,
): (Collection<T>, CollectionAdminCap, ShareCollectionPromise) {
    let collection = Collection {
        id: object::new(ctx),
        kind: kind,
        name: name,
        description: description,
        bucket: bucket,
    };

    let collection_admin_cap = CollectionAdminCap {
        id: object::new(ctx),
        collection_id: collection.id(),
    };

    let promise = ShareCollectionPromise {
        id: object::new(ctx),
        collection_id: collection.id(),
    };

    (collection, collection_admin_cap, promise)
}

public fun share<T>(self: Collection<T>, promise: ShareCollectionPromise) {
    transfer::share_object(self);

    let ShareCollectionPromise { id, .. } = promise;
    id.delete();
}

public fun new_capped_kind(total_supply: u64): CollectionKind {
    CollectionKind::CAPPED { supply: 0, total_supply: total_supply }
}

public fun new_uncapped_kind(): CollectionKind {
    CollectionKind::UNCAPPED { supply: 0 }
}

public fun bucket<T>(self: &Collection<T>): &Bucket {
    &self.bucket
}

public fun bucket_mut<T>(cap: &CollectionAdminCap, self: &mut Collection<T>): &mut Bucket {
    assert!(cap.collection_id == self.id(), EInvalidCollectionAdminCap);
    &mut self.bucket
}

//=== View Functions ===

public fun id<T>(self: &Collection<T>): ID {
    self.id.to_inner()
}

public fun description<T>(self: &Collection<T>): &String {
    &self.description
}

public fun name<T>(self: &Collection<T>): &String {
    &self.name
}

public fun kind<T>(self: &Collection<T>): CollectionKind {
    self.kind
}

public fun supply<T>(self: &Collection<T>): u64 {
    match (self.kind) {
        CollectionKind::CAPPED { supply, .. } => supply,
        CollectionKind::UNCAPPED { supply, .. } => supply,
    }
}

public fun collection_admin_cap_id(self: &CollectionAdminCap): ID {
    self.id.to_inner()
}

public fun collection_admin_cap_collection_id(self: &CollectionAdminCap): ID {
    self.collection_id
}
