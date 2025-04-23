module dos_collection::collection_manager;

use std::string::String;
use std::type_name::{Self, TypeName};
use sui::coin::Coin;
use sui::display;
use sui::dynamic_field as df;
use sui::event::emit;
use sui::package;
use sui::table::{Self, Table};
use sui::transfer::Receiving;
use sui::transfer_policy::TransferPolicy;
use sui::vec_set::{Self, VecSet};
use wal::wal::WAL;
use walrus::blob::Blob;
use walrus::storage_resource::Storage;
use walrus::system::System;

//=== Aliases ===

public use fun collection_manager_admin_cap_authorize as CollectionManagerAdminCap.authorize;
public use fun collection_manager_admin_cap_collection_manager_id as
    CollectionManagerAdminCap.collection_manager_id;
public use fun collection_manager_admin_cap_destroy as CollectionManagerAdminCap.destroy;

//=== Structs ===

public struct COLLECTION_MANAGER has drop {}

public struct CollectionManager has key, store {
    id: UID,
    item_type: TypeName,
    image_uri: String,
    state: CollectionState,
    items: Table<u64, ID>,
    blobs: Table<u256, Option<Blob>>,
    transfer_policies: VecSet<ID>,
}

public struct CollectionManagerAdminCap has key, store {
    id: UID,
    collection_manager_id: ID,
    item_type: TypeName,
}

//=== Enums ===

public enum CollectionState has copy, drop, store {
    INITIALIZATION { target_supply: u64 },
    INITIALIZED,
}

//=== Events ===

public struct CollectionManagerCreatedEvent has copy, drop {
    creator: address,
    collection_manager_id: ID,
    collection_manager_admin_cap_id: ID,
    item_type: TypeName,
}

public struct CollectionManagerItemRegisteredEvent has copy, drop {
    collection_manager_id: ID,
    item_id: ID,
    item_number: u64,
}

public struct CollectionManagerItemUnregisteredEvent has copy, drop {
    collection_manager_id: ID,
    item_id: ID,
    item_number: u64,
}

public struct CollectionManagerBlobSlotReservedEvent has copy, drop {
    collection_manager_id: ID,
    blob_id: u256,
}

//=== Errors ===

const EInvalidCollectionManagerAdminCap: u64 = 10000;
const EInvalidItemType: u64 = 10001;
const EInvalidStateForAction: u64 = 20000;
const ETargetSupplyNotReached: u64 = 20001;
const ETargetSupplyReached: u64 = 20002;
const ENotInitializedState: u64 = 30000;
const ENotInitializationState: u64 = 30001;
const EBlobNotReserved: u64 = 40000;
const EBlobNotExpired: u64 = 40001;
const EInvalidTransferPolicyType: u64 = 50000;
const EInvalidTargetSupply: u64 = 60000;
const ETargetSupplyReached: u64 = 60001;

//=== Init Function ===

fun init(otw: COLLECTION_MANAGER, ctx: &mut TxContext) {
    let publisher = package::claim(otw, ctx);

    let mut display = display::new<CollectionManager>(&publisher, ctx);
    display.add(b"item_type".to_string(), b"{item_type}".to_string());
    display.add(b"creator".to_string(), b"{creator}".to_string());

    transfer::public_transfer(display, ctx.sender());
    transfer::public_transfer(publisher, ctx.sender());
}

//=== Public Functions ===

// Create a new collection.
public(package) fun new<T: key>(
    image_uri: String,
    target_supply: u64,
    ctx: &mut TxContext,
): (CollectionManager, CollectionManagerAdminCap) {
    // Assert that the target supply is greater than 0.
    assert!(target_supply > 0, EInvalidTargetSupply);

    let item_type = type_name::get<T>();

    let collection_manager = CollectionManager {
        id: object::new(ctx),
        item_type: item_type,
        image_uri: image_uri,
        state: CollectionState::INITIALIZATION {
            target_supply: target_supply,
        },
        items: table::new(ctx),
        blobs: table::new(ctx),
        transfer_policies: vec_set::empty(),
    };

    let collection_manager_admin_cap = CollectionManagerAdminCap {
        id: object::new(ctx),
        collection_manager_id: object::id(&collection_manager),
        item_type: item_type,
    };

    emit(CollectionManagerCreatedEvent {
        creator: ctx.sender(),
        collection_manager_id: object::id(&collection_manager),
        collection_manager_admin_cap_id: object::id(&collection_manager_admin_cap),
        item_type: item_type,
    });

    (collection_manager, collection_manager_admin_cap)
}

public fun register_item<T: key + store>(
    self: &mut CollectionManager,
    cap: &CollectionManagerAdminCap,
    number: u64,
    item: &T,
) {
    cap.authorize(self);
    assert_valid_item_type<T>(self);

    match (self.state) {
        CollectionState::INITIALIZATION { target_supply } => {
            // Assert that the quantity of registered items is less than the target supply.
            assert!(self.items.length() < target_supply, ETargetSupplyReached);
            // Register the item to the collection.
            self.items.add(number, object::id(item));
            // Emit CollectionItemRegisteredEvent.
            emit(CollectionManagerItemRegisteredEvent {
                collection_manager_id: self.id.to_inner(),
                item_id: object::id(item),
                item_number: number,
            });
        },
        _ => abort EInvalidStateForAction,
    };
}

public fun unregister_item(
    self: &mut CollectionManager,
    cap: &CollectionManagerAdminCap,
    number: u64,
) {
    cap.authorize(self);

    match (self.state) {
        CollectionState::INITIALIZATION { target_supply } => {
            // Register the item to the collection.
            let item_id = self.items.remove(number);
            // Emit CollectionItemUnregisteredEvent.
            emit(CollectionManagerItemUnregisteredEvent {
                collection_manager_id: self.id.to_inner(),
                item_id: item_id,
                item_number: number,
            });
        },
        _ => abort EInvalidStateForAction,
    };
}

// Link a TransferPolicy to the Collection for discoverability.
public fun link_transfer_policy<T>(
    self: &mut CollectionManager,
    cap: &CollectionManagerAdminCap,
    policy: &TransferPolicy<T>,
) {
    cap.authorize(self);
    assert_valid_item_type<T>(self);
    self.transfer_policies.insert(object::id(policy));
}

// Unlink a TransferPolicy from the Collection.
public fun unlink_transfer_policy(
    self: &mut CollectionManager,
    cap: &CollectionManagerAdminCap,
    policy_id: ID,
) {
    cap.authorize(self);
    self.transfer_policies.remove(&policy_id);
}

// Reserve a storage slot for a Blob by storing the expected Blob ID mapped to option::none().
#[allow(unused_assignment)]
public fun reserve_blob_slot(
    self: &mut CollectionManager,
    cap: &CollectionManagerAdminCap,
    blob_id: u256,
) {
    cap.authorize(self);
    match (self.state) {
        CollectionState::INITIALIZATION { .. } => {
            self.internal_reserve_blob_slot(blob_id);
        },
        _ => abort EInvalidStateForAction,
    }
}

// Reserve multiple Blob slots by storing the expected Blob IDs mapped to option::none().
#[allow(unused_assignment)]
public fun reserve_blob_slots(
    self: &mut CollectionManager,
    cap: &CollectionManagerAdminCap,
    blob_ids: vector<u256>,
) {
    cap.authorize(self);

    match (self.state) {
        CollectionState::INITIALIZATION { .. } => {
            blob_ids.destroy!(|blob_id| self.internal_reserve_blob_slot(blob_id));
        },
        _ => abort EInvalidStateForAction,
    }
}

// Unreserve a Blob slot by removing the Blob ID from the blobs table. Aborts if a Referent<Blob> is already stored.
public fun unreserve_blob_slot(
    self: &mut CollectionManager,
    cap: &CollectionManagerAdminCap,
    blob_id: u256,
) {
    cap.authorize(self);

    match (self.state) {
        CollectionState::INITIALIZATION { .. } => {
            self.internal_unreserve_blob_slot(blob_id);
        },
        _ => abort EInvalidStateForAction,
    }
}

// Unreserve multiple Blob slots by removing the Blob IDs from the blobs table.
public fun unreserve_blob_slots(
    self: &mut CollectionManager,
    cap: &CollectionManagerAdminCap,
    blob_ids: vector<u256>,
) {
    cap.authorize(self);

    match (self.state) {
        CollectionState::INITIALIZATION { .. } => {
            blob_ids.destroy!(|blob_id| self.internal_unreserve_blob_slot(blob_id));
        },
        _ => abort EInvalidStateForAction,
    }
}

// Receive and store a Blob in the CollectionManager.
public fun receive_and_store_blob(self: &mut CollectionManager, blob_to_receive: Receiving<Blob>) {
    let blob = transfer::public_receive(&mut self.id, blob_to_receive);
    let blob_id = blob.blob_id();
    assert!(self.blobs.contains(blob_id), EBlobNotReserved);
    self.blobs.borrow_mut(blob_id).fill(blob);
}

// Store a Blob in the CollectionManager.
public fun store_blob(self: &mut CollectionManager, blob: Blob) {
    let blob_id = blob.blob_id();
    assert!(self.blobs.contains(blob_id), EBlobNotReserved);
    self.blobs.borrow_mut(blob_id).fill(blob);
}

// Remove an expired Blob from the CollectionManager.
public fun remove_blob(self: &mut CollectionManager, blob_id: u256, system: &System): Blob {
    // Remove the Blob from the CollectionManager.
    let old_blob = self.blobs.borrow_mut(blob_id).extract();
    // Assert that the Blob is in or after its expiration epoch by comparing the current epoch to the Blob's end epoch.
    assert!(system.epoch() >= old_blob.end_epoch(), EBlobNotExpired);
    // Return the old Blob.
    old_blob
}

// Extend a Blob's storage duration with a Storage resource.
public fun extend_blob_with_storage(
    self: &mut CollectionManager,
    blob_id: u256,
    storage: Storage,
    system: &mut System,
) {
    let blob_mut = self.blobs.borrow_mut(blob_id).borrow_mut();
    system.extend_blob_with_resource(blob_mut, storage);
}

// Extend a Blob's storage duration with WAL.
public fun extend_blob_with_wal(
    self: &mut CollectionManager,
    blob_id: u256,
    epochs: u32,
    payment: &mut Coin<WAL>,
    system: &mut System,
) {
    let blob_mut = self.blobs.borrow_mut(blob_id).borrow_mut();
    system.extend_blob(blob_mut, epochs, payment);
}

// Destroy a CollectionManagerAdminCap.
public fun collection_manager_admin_cap_destroy(
    cap: CollectionManagerAdminCap,
    self: &mut CollectionManager,
) {
    match (self.state) {
        CollectionState::INITIALIZED => {
            let CollectionManagerAdminCap { id, .. } = cap;
            id.delete();
        },
        _ => abort ENotInitializedState,
    };
}

// Transition from INITIALIZATION to INITIALIZED state once target supply is reached.
//
// Required State: INITIALIZATION
public fun set_initialized_state(self: &mut CollectionManager, cap: &CollectionManagerAdminCap) {
    cap.authorize(self);

    match (self.state) {
        CollectionState::INITIALIZATION { target_supply } => {
            assert!(self.items.length() == target_supply, ETargetSupplyNotReached);
            self.state = CollectionState::INITIALIZED;
        },
        _ => abort EInvalidStateForAction,
    };
}

// Reserve a Blob slot by storing the expected Blob ID mapped to true.
fun internal_reserve_blob_slot(self: &mut CollectionManager, blob_id: u256) {
    self.blobs.add(blob_id, option::none());
    emit(CollectionManagerBlobSlotReservedEvent {
        collection_manager_id: self.id.to_inner(),
        blob_id: blob_id,
    });
}

// Unreserve a Blob slot by removing the Blob ID from the blobs table.
fun internal_unreserve_blob_slot(self: &mut CollectionManager, blob_id: u256) {
    self.blobs.remove(blob_id).destroy_none();
}

//=== View Functions ===

public fun blobs(self: &CollectionManager): &Table<u256, Option<Blob>> {
    &self.blobs
}

public fun collection_metadata_id(self: &CollectionManager): ID {
    *df::borrow<vector<u8>, ID>(&self.id, b"COLLECTION_METADATA_ID")
}

public fun image_uri(self: &CollectionManager): String {
    self.image_uri
}

public fun item_type(self: &CollectionManager): TypeName {
    self.item_type
}

public fun items(self: &CollectionManager): &Table<u64, ID> {
    &self.items
}

public fun transfer_policies(self: &CollectionManager): &VecSet<ID> {
    &self.transfer_policies
}

public fun collection_manager_admin_cap_collection_manager_id(cap: &CollectionManagerAdminCap): ID {
    cap.collection_manager_id
}

public(package) fun uid_mut(self: &mut CollectionManager): &mut UID {
    &mut self.id
}

//=== Assert Functions ===

public fun assert_blob_reserved(self: &CollectionManager, blob_id: u256) {
    assert!(self.blobs.contains(blob_id), EBlobNotReserved);
}

public fun assert_state_initialization(self: &CollectionManager) {
    match (self.state) {
        CollectionState::INITIALIZATION { .. } => (),
        _ => abort ENotInitializationState,
    };
}

public fun assert_state_initialized(self: &CollectionManager) {
    match (self.state) {
        CollectionState::INITIALIZED => (),
        _ => abort ENotInitializedState,
    };
}

fun assert_valid_item_type<T>(self: &CollectionManager) {
    assert!(type_name::get<T>() == self.item_type, EInvalidItemType);
}

//=== Private Functions ===

fun collection_manager_admin_cap_authorize(
    self: &CollectionManager,
    cap: &CollectionManagerAdminCap,
) {
    cap.authorize(self);
}
