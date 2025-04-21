module dos_collection::collection;

use std::string::String;
use std::type_name::{Self, TypeName};
use sui::display;
use sui::event::emit;
use sui::package::{Self, Publisher};
use sui::table::{Self, Table};
use sui::transfer_policy::TransferPolicy;
use sui::vec_set::{Self, VecSet};
use walrus::blob::Blob;

//=== Aliases ===

public use fun collection_admin_cap_collection_id as CollectionAdminCap.collection_id;
public use fun collection_admin_cap_destroy as CollectionAdminCap.destroy;

//=== Structs ===

public struct COLLECTION has drop {}

public struct Collection has key, store {
    id: UID,
    item_type: TypeName,
    state: CollectionState,
    creator: address,
    name: String,
    description: String,
    external_url: String,
    image_uri: String,
    total_supply: u64,
    items: Table<u64, ID>,
    // Stores relationships between Blob IDs and Blob Object IDs.
    blobs: Table<u256, Option<ID>>,
    transfer_policies: VecSet<ID>,
}

public struct CollectionAdminCap has key, store {
    id: UID,
    collection_id: ID,
    item_type: TypeName,
}

public enum CollectionState has copy, drop, store {
    ITEM_REGISTRATION { registered_count: u64 },
    INITIALIZED,
}

//=== Events ===

public struct CollectionCreatedEvent has copy, drop {
    creator: address,
    collection_id: ID,
    collection_admin_cap_id: ID,
    item_type: TypeName,
}

public struct CollectionItemRegisteredEvent has copy, drop {
    collection_id: ID,
    item_id: ID,
    item_number: u64,
}

public struct CollectionItemUnregisteredEvent has copy, drop {
    collection_id: ID,
    item_id: ID,
    item_number: u64,
}

public struct CollectionBlobLinkedEvent has copy, drop {
    collection_id: ID,
    blob_id: u256,
    blob_object_id: ID,
}

public struct CollectionBlobSlotReservedEvent has copy, drop {
    collection_id: ID,
    blob_id: u256,
}

public struct CollectionBlobSlotsReservedEvent has copy, drop {
    collection_id: ID,
    blob_ids: vector<u256>,
}

public struct CollectionBlobSlotUnreservedEvent has copy, drop {
    collection_id: ID,
    blob_id: u256,
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
const EBlobNotStored: u64 = 40002;
const EInvalidTransferPolicyType: u64 = 50001;

//=== Init Function ===

fun init(otw: COLLECTION, ctx: &mut TxContext) {
    let publisher = package::claim(otw, ctx);

    let mut display = display::new<Collection>(&publisher, ctx);
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

// Create a new collection.
public fun new<T: key + store>(
    publisher: &Publisher,
    creator: address,
    name: String,
    description: String,
    external_url: String,
    image_uri: String,
    total_supply: u64,
    ctx: &mut TxContext,
): (Collection, CollectionAdminCap) {
    assert!(publisher.from_module<T>(), EInvalidPublisher);

    let item_type = type_name::get<T>();

    let collection = Collection {
        id: object::new(ctx),
        state: CollectionState::ITEM_REGISTRATION { registered_count: 0 },
        name: name,
        creator: creator,
        description: description,
        item_type: item_type,
        external_url: external_url,
        image_uri: image_uri,
        total_supply: total_supply,
        items: table::new(ctx),
        blobs: table::new(ctx),
        transfer_policies: vec_set::empty(),
    };

    let collection_admin_cap = CollectionAdminCap {
        id: object::new(ctx),
        collection_id: collection.id.to_inner(),
        item_type: item_type,
    };

    emit(CollectionCreatedEvent {
        creator: creator,
        collection_id: collection.id.to_inner(),
        collection_admin_cap_id: object::id(&collection_admin_cap),
        item_type: item_type,
    });

    (collection, collection_admin_cap)
}

public fun register_item<T: key + store>(
    self: &mut Collection,
    cap: &CollectionAdminCap,
    number: u64,
    item: &T,
) {
    assert!(cap.collection_id == self.id.to_inner(), EInvalidCollectionAdminCap);
    assert!(cap.item_type == type_name::get<T>(), EInvalidItemType);

    match (&mut self.state) {
        CollectionState::ITEM_REGISTRATION { registered_count } => {
            // Assert that the quantity of registered items is less than the target supply.
            assert!(self.items.length() < self.total_supply, ECollectionAlreadyInitialized);
            // Register the item to the collection.
            self.items.add(number, object::id(item));
            // Set current supply to the new quantity of registered items.
            *registered_count = self.items.length();

            emit(CollectionItemRegisteredEvent {
                collection_id: self.id.to_inner(),
                item_id: object::id(item),
                item_number: number,
            });
        },
        _ => abort ECollectionAlreadyInitialized,
    };
}

public fun unregister_item(self: &mut Collection, cap: &CollectionAdminCap, number: u64) {
    assert!(cap.collection_id == self.id.to_inner(), EInvalidCollectionAdminCap);

    match (&mut self.state) {
        CollectionState::ITEM_REGISTRATION { registered_count } => {
            // Assert that the quantity of registered items is less than the target supply.
            assert!(self.items.length() < self.total_supply, ECollectionAlreadyInitialized);
            // Register the item to the collection.
            let item_id = self.items.remove(number);
            // Set current supply to the new quantity of registered items.
            *registered_count = self.items.length();

            emit(CollectionItemUnregisteredEvent {
                collection_id: self.id.to_inner(),
                item_id: item_id,
                item_number: number,
            });
        },
        _ => abort ECollectionAlreadyInitialized,
    };
}

// Link a TransferPolicy to the Collection for discoverability.
public fun link_transfer_policy<T>(
    self: &mut Collection,
    cap: &CollectionAdminCap,
    policy: &TransferPolicy<T>,
) {
    assert!(cap.collection_id == self.id.to_inner(), EInvalidCollectionAdminCap);
    assert!(type_name::get<T>() == self.item_type, EInvalidTransferPolicyType);
    self.transfer_policies.insert(object::id(policy));
}

// Unlink a TransferPolicy from the Collection.
public fun unlink_transfer_policy(self: &mut Collection, cap: &CollectionAdminCap, policy_id: ID) {
    assert!(cap.collection_id == self.id.to_inner(), EInvalidCollectionAdminCap);
    self.transfer_policies.remove(&policy_id);
}

// Reserve a storage slot for a Blob by storing the expected Blob ID mapped to option::none().
#[allow(unused_assignment)]
public fun reserve_blob_slot(self: &mut Collection, cap: &CollectionAdminCap, blob_id: u256) {
    assert!(cap.collection_id == self.id.to_inner(), EInvalidCollectionAdminCap);
    self.internal_reserve_blob_slot(blob_id);
}

#[allow(unused_assignment)]
public fun reserve_blob_slots(
    self: &mut Collection,
    cap: &CollectionAdminCap,
    blob_ids: vector<u256>,
) {
    assert!(cap.collection_id == self.id.to_inner(), EInvalidCollectionAdminCap);
    blob_ids.destroy!(|blob_id| self.internal_reserve_blob_slot(blob_id));
    emit(CollectionBlobSlotsReservedEvent {
        collection_id: self.id.to_inner(),
        blob_ids: blob_ids,
    });
}

// Unreserve a Blob slot by removing the Blob ID from the blobs table.
//
// Required State: BLOB_RESERVATION
public fun unreserve_blob_slot(self: &mut Collection, blob_id: u256) {
    self.blobs.remove(blob_id).destroy_none();

    emit(CollectionBlobSlotUnreservedEvent {
        collection_id: self.id.to_inner(),
        blob_id: blob_id,
    });
}

// Link a Blob ID to the ID of the corresponding Blob object for discoverability.
public fun link_blob_object_id(self: &mut Collection, cap: &CollectionAdminCap, blob: &Blob) {
    assert!(cap.collection_id == self.id.to_inner(), EInvalidCollectionAdminCap);
    self.blobs.borrow_mut(blob.blob_id()).swap_or_fill(object::id(blob));

    emit(CollectionBlobLinkedEvent {
        collection_id: self.id.to_inner(),
        blob_id: blob.blob_id(),
        blob_object_id: object::id(blob),
    });
}

// Destroy a CollectionAdminCap to renounce ownership of the Collection.
// Only callable if the Collection is initialized.
//
// Required State: INITIALIZED
public fun collection_admin_cap_destroy(cap: CollectionAdminCap, self: &mut Collection) {
    match (self.state) {
        CollectionState::INITIALIZED => {
            let CollectionAdminCap { id, .. } = cap;
            id.delete();
        },
        _ => abort ECollectionNotInitialized,
    };
}

// Transition from ITEM_REGISTRATION to INITIALIZED state once target supply is reached.
//
// Required State: ITEM_REGISTRATION
public fun set_initialized_state(self: &mut Collection) {
    match (self.state) {
        CollectionState::ITEM_REGISTRATION { registered_count } => {
            assert!(registered_count == self.total_supply, EItemRegistrationTargetSupplyNotReached);
            self.state = CollectionState::INITIALIZED;
        },
        _ => abort ENotItemRegistrationState,
    };
}

fun internal_reserve_blob_slot(self: &mut Collection, blob_id: u256) {
    self.blobs.add(blob_id, option::none());
    emit(CollectionBlobSlotReservedEvent {
        collection_id: self.id.to_inner(),
        blob_id: blob_id,
    });
}

//=== View Functions ===

public fun creator(self: &Collection): address {
    self.creator
}

public fun description(self: &Collection): String {
    self.description
}

public fun external_url(self: &Collection): String {
    self.external_url
}

public fun image_uri(self: &Collection): String {
    self.image_uri
}

public fun name(self: &Collection): String {
    self.name
}

public fun collection_admin_cap_collection_id(cap: &CollectionAdminCap): ID {
    cap.collection_id
}

public fun registered_count(self: &Collection): u64 {
    match (self.state) {
        CollectionState::ITEM_REGISTRATION { registered_count, .. } => registered_count,
        _ => abort ECollectionNotInitialized,
    }
}

public fun total_supply(self: &Collection): u64 {
    self.total_supply
}

//=== Assert Functions ===

public fun assert_blob_reserved(self: &Collection, blob_id: u256) {
    assert!(self.blobs.contains(blob_id), EBlobNotReserved);
}

public fun assert_blob_stored(self: &Collection, blob_id: u256) {
    assert!(self.blobs.borrow(blob_id).is_some(), EBlobNotStored);
}

public fun assert_state_item_registration(self: &Collection) {
    match (self.state) {
        CollectionState::ITEM_REGISTRATION { .. } => (),
        _ => abort ENotItemRegistrationState,
    };
}

public fun assert_state_initialized(self: &Collection) {
    match (self.state) {
        CollectionState::INITIALIZED => (),
        _ => abort ENotInitializedState,
    };
}

// Assert that a CollectionAdminCap is valid for the Collection.
public fun assert_valid_collection_admin_cap(self: &Collection, cap: &CollectionAdminCap) {
    assert!(cap.collection_id == self.id.to_inner(), EInvalidCollectionAdminCap);
}
