# Sample Review: Add user creation endpoint

This is a worked example showing a PR diff and the corresponding review. The review uses the bundled checklist and comment template.

## The PR diff

```diff
diff --git a/src/users/api/create-user.go b/src/users/api/create-user.go
new file mode 100644
index 0000000..a1b2c3d
--- /dev/null
+++ b/src/users/api/create-user.go
@@ -0,0 +1,34 @@
+package api
+
+import (
+	"encoding/json"
+	"net/http"
+)
+
+type CreateUserRequest struct {
+	Name  string `json:"name"`
+	Email string `json:"email"`
+}
+
+func CreateUserHandler(w http.ResponseWriter, r *http.Request) {
+	var req CreateUserRequest
+	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
+		http.Error(w, "bad request", http.StatusBadRequest)
+		return
+	}
+
+	if req.Name == "" {
+		http.Error(w, "name is required", http.StatusBadRequest)
+		return
+	}
+
+	userID := fmt.Sprintf("user-%d", len(store.users)+1)
+	store.users[userID] = req
+
+	w.WriteHeader(http.StatusCreated)
+	json.NewEncoder(w).Encode(map[string]string{
+		"id":    userID,
+		"name":  req.Name,
+	})
+}
```

## The review

# PR Review: Add user creation endpoint

## Summary

The handler follows a straightforward create pattern and correctly returns 400 for a missing name. However, there are blocking issues with input validation, error handling, and concurrent safety that must be addressed before merge.

## Blocking

### Email is not validated

**File:** `src/users/api/create-user.go` (line 31)

**Problem:** The handler accepts any value for `Email`, including empty strings and malformed addresses. An invalid email stored now will cause failures downstream when notifications, login flows, or account recovery depend on a valid address.

**Fix:** Validate `Email` is non-empty and matches a basic email pattern. Return 400 with a specific message for invalid email.

### Missing concurrency protection on the user store

**File:** `src/users/api/create-user.go` (line 26)

**Problem:** `store.users` is read and written without synchronisation. Two concurrent requests will see the same `len(store.users)` and produce the same `userID`, causing one request to silently overwrite the other.

**Fix:** Guard access to `store.users` with a mutex, or use an atomic counter for ID generation.

### Error from json.NewDecoder is not wrapped with context

**File:** `src/users/api/create-user.go` (line 17)

**Problem:** The raw decode error is discarded. If the body is malformed, the client receives a generic "bad request" with no indication of what went wrong. This makes debugging difficult for the API consumer.

**Fix:** Log the decode error server-side for diagnostics. Optionally include a hint in the response body (e.g. "request body must be valid JSON").

### Email is returned in the response but not declared in the response struct

**File:** `src/users/api/create-user.go` (lines 30-32)

**Problem:** The response map includes `id` and `name` but omits `email`. The client cannot confirm which email was stored without a follow-up GET. This is inconsistent with the request shape.

**Fix:** Include `email` in the response, or explicitly document that the create response is a partial representation.

## Non-blocking

### User ID generation is fragile

**File:** `src/users/api/create-user.go` (line 26)

**Suggestion:** The ID scheme `user-N` based on store length creates non-unique IDs under concurrent access (see blocking finding) and leaks internal state (user count). Consider using a UUID or ULID.

## Questions

- Is there an existing email validation utility in the codebase, or should one be added?
- Should the handler set a `Content-Type: application/json` header on the response?

## Positive

- The handler correctly separates request decoding from validation and from response writing — each concern has its own block.
- Returning 400 for a missing `name` with a specific error message follows good API design.
- The response writes `201 Created` (not `200 OK`), which is the correct status for resource creation.
