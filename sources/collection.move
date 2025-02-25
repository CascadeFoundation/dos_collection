module dos_collection::collection;

use dos_bucket::bucket::Bucket;
use dos_collection::collection_admin_cap::{Self, CollectionAdminCap};
use std::string::String;

//=== Structs ===

public struct COLLECTION has drop {}

public struct Collection<phantom T> has key {
    id: UID,
    kind: CollectionKind,
    name: String,
    description: String,
    unit_name: String,
    unit_description: String,
    bucket: Bucket,
}

public struct ShareCollectionPromise has key {
    id: UID,
    collection_id: ID,
}

public enum CollectionKind has copy, drop, store {
    CAPPED { supply: u64, total_supply: u64 },
    UNCAPPED { supply: u64 },
}

//=== Public Functions ===

public fun new<T>(
    kind: CollectionKind,
    name: String,
    description: String,
    unit_name: String,
    unit_description: String,
    bucket: Bucket,
    ctx: &mut TxContext,
): (Collection<T>, CollectionAdminCap, ShareCollectionPromise) {
    let collection = Collection {
        id: object::new(ctx),
        kind: kind,
        name: name,
        description: description,
        unit_name: unit_name,
        unit_description: unit_description,
        bucket: bucket,
    };

    let collection_admin_cap = collection_admin_cap::new(collection.id(), ctx);

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
    cap.authorize(self.id());
    &mut self.bucket
}

public fun uid<T>(self: &Collection<T>, cap: &CollectionAdminCap): &UID {
    cap.authorize(self.id());
    &self.id
}

public fun uid_mut<T>(self: &mut Collection<T>, cap: &CollectionAdminCap): &mut UID {
    cap.authorize(self.id());
    &mut self.id
}

//=== View Functions ===

public fun id<T>(self: &Collection<T>): ID {
    self.id.to_inner()
}

public fun description<T>(self: &Collection<T>): &String {
    &self.description
}

public fun kind<T>(self: &Collection<T>): CollectionKind {
    self.kind
}

public fun name<T>(self: &Collection<T>): String {
    self.name
}

public fun supply<T>(self: &Collection<T>): u64 {
    match (self.kind) {
        CollectionKind::CAPPED { supply, .. } => supply,
        CollectionKind::UNCAPPED { supply, .. } => supply,
    }
}

public fun total_supply<T>(self: &Collection<T>): u64 {
    match (self.kind) {
        CollectionKind::CAPPED { total_supply, .. } => total_supply,
        CollectionKind::UNCAPPED { .. } => 18446744073709551615,
    }
}

public fun unit_description<T>(self: &Collection<T>): String {
    self.unit_description
}

public fun unit_name<T>(self: &Collection<T>): String {
    self.unit_name
}
