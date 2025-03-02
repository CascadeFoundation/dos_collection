module dos_collection::collection;

use dos_bucket::bucket::{Self, BucketAdminCap};
use std::string::String;
use sui::transfer::Receiving;
use sui::types;

//=== Aliases ===

public use fun collection_admin_cap_authorize as CollectionAdminCap.authorize;
public use fun collection_admin_cap_collection_id as CollectionAdminCap.collection_id;
public use fun collection_admin_cap_id as CollectionAdminCap.id;

//=== Structs ===

public struct COLLECTION has drop {}

public struct Collection<phantom T> has key {
    id: UID,
    kind: CollectionKind,
    name: String,
    description: String,
    bucket_id: ID,
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

//=== Errors ===

const EInvalidWitness: u64 = 0;
const EInvalidCollection: u64 = 1;

//=== Public Functions ===

public fun new<T: drop>(
    witness: T,
    kind: CollectionKind,
    name: String,
    description: String,
    ctx: &mut TxContext,
): (Collection<T>, CollectionAdminCap, ShareCollectionPromise, BucketAdminCap) {
    assert!(types::is_one_time_witness(&witness), EInvalidWitness);

    let (bucket, bucket_admin_cap) = bucket::new(ctx);

    let collection = Collection<T> {
        id: object::new(ctx),
        kind: kind,
        name: name,
        description: description,
        bucket_id: bucket.id(),
    };

    let collection_admin_cap = CollectionAdminCap {
        id: object::new(ctx),
        collection_id: collection.id(),
    };

    let promise = ShareCollectionPromise {
        id: object::new(ctx),
        collection_id: collection.id(),
    };

    transfer::public_share_object(bucket);

    (collection, collection_admin_cap, promise, bucket_admin_cap)
}

public fun receive<T: key + store>(
    self: &mut Collection<T>,
    cap: &CollectionAdminCap,
    obj_to_receive: Receiving<T>,
): T {
    cap.authorize(self.id());

    transfer::public_receive(&mut self.id, obj_to_receive)
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

public fun bucket_id<T>(self: &Collection<T>): ID {
    self.bucket_id
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

public fun collection_admin_cap_collection_id(cap: &CollectionAdminCap): ID { cap.collection_id }

public fun collection_admin_cap_id(cap: &CollectionAdminCap): ID { cap.id.to_inner() }

//=== Private Functions ===

fun collection_admin_cap_authorize(cap: &CollectionAdminCap, collection_id: ID) {
    assert!(cap.collection_id == collection_id, EInvalidCollection);
}
