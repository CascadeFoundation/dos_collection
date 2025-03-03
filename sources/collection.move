module dos_collection::collection;

use std::string::String;
use sui::package::Publisher;
use sui::transfer::Receiving;
use sui::url::Url;

//=== Aliases ===

public use fun collection_admin_cap_authorize as CollectionAdminCap.authorize;
public use fun collection_admin_cap_collection_id as CollectionAdminCap.collection_id;
public use fun collection_admin_cap_id as CollectionAdminCap.id;

//=== Structs ===

public struct COLLECTION has drop {}

public struct Collection<phantom T: key + store> has key, store {
    id: UID,
    creator: address,
    name: String,
    description: String,
    external_url: Url,
    image_uri: u256,
    supply: u64,
}

public struct CollectionAdminCap<phantom T: key + store> has key, store {
    id: UID,
    collection_id: ID,
}

//=== Errors ===

const EInvalidPublisher: u64 = 0;
const EInvalidCollection: u64 = 1;

//=== Public Functions ===

public fun new<T: key + store>(
    publisher: &Publisher,
    name: String,
    creator: address,
    description: String,
    external_url: Url,
    image_uri: u256,
    supply: u64,
    ctx: &mut TxContext,
): (Collection<T>, CollectionAdminCap<T>) {
    assert!(publisher.from_module<T>() == true, EInvalidPublisher);

    let collection = Collection<T> {
        id: object::new(ctx),
        name: name,
        creator: creator,
        description: description,
        external_url: external_url,
        image_uri: image_uri,
        supply: supply,
    };

    let collection_admin_cap = CollectionAdminCap {
        id: object::new(ctx),
        collection_id: collection.id(),
    };

    (collection, collection_admin_cap)
}

public fun receive<T: key + store>(
    self: &mut Collection<T>,
    cap: &CollectionAdminCap<T>,
    obj_to_receive: Receiving<T>,
): T {
    cap.authorize(self.id());

    transfer::public_receive(&mut self.id, obj_to_receive)
}

public fun uid<T: key + store>(self: &Collection<T>, cap: &CollectionAdminCap<T>): &UID {
    cap.authorize(self.id());

    &self.id
}

public fun uid_mut<T: key + store>(
    self: &mut Collection<T>,
    cap: &CollectionAdminCap<T>,
): &mut UID {
    cap.authorize(self.id());
    &mut self.id
}

//=== View Functions ===

public fun id<T: key + store>(self: &Collection<T>): ID {
    self.id.to_inner()
}

public fun creator<T: key + store>(self: &Collection<T>): address {
    self.creator
}

public fun name<T: key + store>(self: &Collection<T>): String {
    self.name
}

public fun description<T: key + store>(self: &Collection<T>): String {
    self.description
}

public fun external_url<T: key + store>(self: &Collection<T>): &Url {
    &self.external_url
}

public fun image_uri<T: key + store>(self: &Collection<T>): u256 {
    self.image_uri
}

public fun supply<T: key + store>(self: &Collection<T>): u64 {
    self.supply
}

public fun collection_admin_cap_collection_id<T: key + store>(cap: &CollectionAdminCap<T>): ID {
    cap.collection_id
}

public fun collection_admin_cap_id<T: key + store>(cap: &CollectionAdminCap<T>): ID {
    cap.id.to_inner()
}

//=== Private Functions ===

fun collection_admin_cap_authorize<T: key + store>(cap: &CollectionAdminCap<T>, collection_id: ID) {
    assert!(cap.collection_id == collection_id, EInvalidCollection);
}
