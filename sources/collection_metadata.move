module dos_collection::collection_metadata;

use std::string::String;
use std::type_name::{Self, TypeName};
use sui::display;
use sui::event::emit;
use sui::package::{Self, Publisher};

//=== Structs ===

public struct COLLECTION_METADATA has drop {}

public struct CollectionMetadata has key, store {
    id: UID,
    item_type: TypeName,
    creator: address,
    name: String,
    description: String,
    external_url: String,
    image_uri: String,
}

//=== Events ===

public struct CollectionMetadataCreatedEvent has copy, drop {
    creator: address,
    collection_metadata_id: ID,
    item_type: TypeName,
}

//=== Constants ===

const DISPLAY_IMAGE_URL: vector<u8> = b"https://testnet.wal.gg/{image_uri}";

//=== Errors ===

const EInvalidCollectionAdminCap: u64 = 10001;
const ECollectionAlreadyInitialized: u64 = 10002;
const ECollectionNotInitialized: u64 = 10003;
const ENotItemRegistrationState: u64 = 20001;
const EItemRegistrationTargetSupplyNotReached: u64 = 20002;
const ENotInitializedState: u64 = 30001;
const EInvalidItemType: u64 = 30002;
const EInvalidPublisher: u64 = 30003;
const EBlobNotReserved: u64 = 40001;
const EInvalidTransferPolicyType: u64 = 50001;

//=== Init Function ===

fun init(otw: COLLECTION_METADATA, ctx: &mut TxContext) {
    let publisher = package::claim(otw, ctx);

    let mut display = display::new<CollectionMetadata>(&publisher, ctx);
    display.add(b"item_type".to_string(), b"{item_type}".to_string());
    display.add(b"creator".to_string(), b"{creator}".to_string());
    display.add(b"name".to_string(), b"{name}".to_string());
    display.add(b"description".to_string(), b"{description}".to_string());
    display.add(b"external_url".to_string(), b"{external_url}".to_string());
    display.add(b"image_uri".to_string(), b"walrus://{image_uri}".to_string());
    display.add(b"image_url".to_string(), DISPLAY_IMAGE_URL.to_string());

    transfer::public_transfer(display, ctx.sender());
    transfer::public_transfer(publisher, ctx.sender());
}

//=== Public Functions ===

public(package) fun new<T: key>(
    creator: address,
    name: String,
    description: String,
    external_url: String,
    image_uri: String,
    ctx: &mut TxContext,
): CollectionMetadata {
    let item_type = type_name::get<T>();

    let collection_metadata = CollectionMetadata {
        id: object::new(ctx),
        item_type: item_type,
        creator: creator,
        name: name,
        description: description,
        external_url: external_url,
        image_uri: image_uri,
    };

    emit(CollectionMetadataCreatedEvent {
        creator: creator,
        collection_metadata_id: object::id(&collection_metadata),
        item_type: item_type,
    });

    collection_metadata
}

public(package) fun uid_mut(self: &mut CollectionMetadata): &mut UID {
    &mut self.id
}

public fun creator(self: &CollectionMetadata): address {
    self.creator
}

public fun description(self: &CollectionMetadata): String {
    self.description
}

public fun external_url(self: &CollectionMetadata): String {
    self.external_url
}

public fun image_uri(self: &CollectionMetadata): String {
    self.image_uri
}

public fun item_type(self: &CollectionMetadata): TypeName {
    self.item_type
}

public fun name(self: &CollectionMetadata): String {
    self.name
}
