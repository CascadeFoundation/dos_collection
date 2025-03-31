module dos_collection::collection;

use std::string::String;
use std::type_name::{Self, TypeName};
use sui::dynamic_field as df;
use sui::event::emit;
use sui::package::{Self, Publisher};
use sui::url::Url;

//=== Aliases ===

public use fun collection_admin_cap_collection_id as CollectionAdminCap.collection_id;

//=== Structs ===

public struct COLLECTION has drop {}

public struct Collection<phantom T> has key, store {
    id: UID,
    creator: address,
    name: String,
    description: String,
    item_type: TypeName,
    external_url: Url,
    image_uri: String,
    supply: u64,
}

public struct CollectionAdminCap<phantom T> has key, store {
    id: UID,
    collection_id: ID,
}

//=== Events ===

public struct CollectionCreatedEvent has copy, drop {
    creator: address,
    collection_id: ID,
    collection_admin_cap_id: ID,
    collection_type: TypeName,
}

//=== Errors ===

const EInvalidPublisher: u64 = 0;
const EInvalidCollectionAdminCap: u64 = 1;

//=== Init Function ===

fun init(otw: COLLECTION, ctx: &mut TxContext) {
    package::claim_and_keep(otw, ctx);
}

//=== Public Functions ===

public fun new<T>(
    publisher: &Publisher,
    name: String,
    creator: address,
    description: String,
    external_url: Url,
    image_uri: String,
    supply: u64,
    ctx: &mut TxContext,
): (Collection<T>, CollectionAdminCap<T>) {
    assert!(publisher.from_module<T>() == true, EInvalidPublisher);

    let collection = Collection<T> {
        id: object::new(ctx),
        name: name,
        creator: creator,
        description: description,
        item_type: type_name::get<T>(),
        external_url: external_url,
        image_uri: image_uri,
        supply: supply,
    };

    let collection_admin_cap = CollectionAdminCap {
        id: object::new(ctx),
        collection_id: collection.id.to_inner(),
    };

    emit(CollectionCreatedEvent {
        collection_id: collection.id.to_inner(),
        collection_admin_cap_id: object::id(&collection_admin_cap),
        collection_type: type_name::get<T>(),
        creator: creator,
    });

    (collection, collection_admin_cap)
}

public fun add_metadata<T: key + store, K: copy + drop + store, V: drop + store>(
    self: &mut Collection<T>,
    cap: &CollectionAdminCap<T>,
    key: K,
    value: V,
) {
    assert!(cap.collection_id == self.id.to_inner(), EInvalidCollectionAdminCap);
    df::add(&mut self.id, key, value);
}

public fun remove_metadata<T: key + store, K: copy + drop + store, V: drop + store>(
    self: &mut Collection<T>,
    cap: &CollectionAdminCap<T>,
    key: K,
) {
    assert!(cap.collection_id == self.id.to_inner(), EInvalidCollectionAdminCap);
    df::remove<K, V>(&mut self.id, key);
}

//=== View Functions ===

public fun creator<T>(self: &Collection<T>): address {
    self.creator
}

public fun name<T>(self: &Collection<T>): String {
    self.name
}

public fun description<T>(self: &Collection<T>): String {
    self.description
}

public fun external_url<T>(self: &Collection<T>): &Url {
    &self.external_url
}

public fun image_uri<T>(self: &Collection<T>): String {
    self.image_uri
}

public fun supply<T>(self: &Collection<T>): u64 {
    self.supply
}

public fun collection_admin_cap_collection_id<T>(cap: &CollectionAdminCap<T>): ID {
    cap.collection_id
}
