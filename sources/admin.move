module dos_collection::admin;

public struct ADMIN has drop {}

public struct AdminCap has key, store {
    id: UID,
    collection_id: ID,
}

public fun id(self: &AdminCap): ID {
    self.id.to_inner()
}

public fun collection_id(self: &AdminCap): ID {
    self.collection_id
}
