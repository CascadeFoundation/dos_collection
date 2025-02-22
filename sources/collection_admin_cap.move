module dos_collection::collection_admin_cap;

public struct CollectionAdminCap has key, store {
    id: UID,
    collection_id: ID,
}

const EInvalidCollection: u64 = 0;

public fun authorize(self: &CollectionAdminCap, collection_id: ID) {
    assert!(self.collection_id == collection_id, EInvalidCollection);
}

public fun id(self: &CollectionAdminCap): ID {
    self.id.to_inner()
}

public fun collection_id(self: &CollectionAdminCap): ID {
    self.collection_id
}

public(package) fun new(collection_id: ID, ctx: &mut TxContext): CollectionAdminCap {
    CollectionAdminCap {
        id: object::new(ctx),
        collection_id: collection_id,
    }
}
