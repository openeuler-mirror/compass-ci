# id(=job_id)

## meaning

A unique sequence number in a lab.
When user submit a job, scheduler save a job document in ES DB.

Format: `yyMMddHHmmssSSS + worker_id_padded`

## use example
```
es-find id=$job_id
es-jobs id=$job_id
```

# Job ID Generation

The job ID generation system incorporates **Worker IDs** and **Cluster Size** to ensure unique, chronologically ordered IDs across a distributed system.

---

## 1. Overview

The job ID generation system is designed to:
- Generate **unique IDs** across multiple workers in a cluster.
- Ensure IDs are **chronologically ordered** when merged into a shared database.
- Support **scalability** by allowing workers to operate independently without conflicts.

Each job ID consists of:
- A **timestamp** (`yyMMddHHmmssSSS`).
- A **worker ID** (padded to match the cluster size).

---

## 2. Key Concepts

### 2.1 Worker ID
- Represents a unique identifier for a worker in the cluster.
- Must be an integer between `0` and `cluster_size - 1`.
- Examples:
  - For `cluster_size=10`, valid worker IDs are `0` to `9`.
  - For `cluster_size=100`, valid worker IDs are `0` to `99`.

### 2.2 Cluster Size
- Defines the maximum number of workers in the cluster.
- Must be one of `10`, `100`, or `1000`.
- Determines the padding length for the worker ID:
  - `10`: 1-digit worker ID (e.g., `0`, `1`, ..., `9`).
  - `100`: 2-digit worker ID (e.g., `00`, `01`, ..., `99`).
  - `1000`: 3-digit worker ID (e.g., `000`, `001`, ..., `999`).

### 2.3 Job ID Format
- Combines a **timestamp** and a **worker ID**.
- Format: `yyMMddHHmmssSSS + worker_id_padded`.
- Example:
  - Timestamp: `250225123114723` (March 25, 2025, 12:31:14.723).
  - Worker ID: `05` (for `cluster_size=100`).
  - Job ID: `25022512311472305`.

---

## 3. Usage

### 3.1 Configuration

1. **Set Worker ID**:
   - Each worker must have a unique `worker_id` within the cluster.
   - Example:
     ```yaml
     worker_id: 5
     cluster_size: 100
     ```

2. **Set Cluster Size**:
   - All workers in the cluster must use the same `cluster_size`.
   - Example worker 2:
     ```yaml
     worker_id: 6
     cluster_size: 100
     ```

3. **Validation**:
   - The system validates that:
     - `worker_id` is within the allowed range for the `cluster_size`.
     - `cluster_size` is one of `10`, `100`, or `1000`.

### 3.2 Generating Job IDs
- Use the `get_job_id` method to generate a unique job ID.
- Example:
  ```crystal
  job_id = Sched.get_job_id
  puts job_id # => "25022512311472305"
  ```

### 3.3 Handling Conflicts
- If a generated job ID conflicts with a previously used ID (e.g., due to clock skew or high-frequency generation), the system increments the ID by the `cluster_size` to ensure uniqueness.
- Example:
  - Last job ID: `25022512311472305`.
  - New job ID: `25022512311472405` (incremented by `cluster_size=100`).

---

## 4. Examples

### Example 1: Small Cluster (`cluster_size=10`)
- Worker ID: `3`.
- Job ID: `2502251231147233`.

### Example 2: Medium Cluster (`cluster_size=100`)
- Worker ID: `42`.
- Job ID: `25022512311472342`.

### Example 3: Large Cluster (`cluster_size=1000`)
- Worker ID: `123`.
- Job ID: `250225123114723123`.

---

## 5. Best Practices

1. **Consistent Configuration**:
   - Ensure all workers in the cluster use the same `cluster_size`.
   - Assign unique `worker_id`s to each worker.

2. **Clock Synchronization**:
   - Use synchronized clocks across workers to avoid timestamp conflicts.

3. **Avoid High-Frequency Conflicts**:
   - If generating IDs at a very high frequency, ensure the `cluster_size` is large enough to handle the workload.

4. **Error Handling**:
   - Handle validation errors (e.g., invalid `worker_id` or `cluster_size`) during initialization.

---

## 6. Troubleshooting

### Issue: Duplicate Job IDs
- **Cause**: Clock skew or high-frequency ID generation.
- **Solution**: The system automatically increments the ID by the `cluster_size` to resolve conflicts.

### Issue: Invalid Worker ID
- **Cause**: `worker_id` is outside the allowed range for the `cluster_size`.
- **Solution**: Ensure the `worker_id` is within the range `0` to `cluster_size - 1`.

### Issue: Invalid Cluster Size
- **Cause**: `cluster_size` is not one of `10`, `100`, or `1000`.
- **Solution**: Use a valid `cluster_size`.

---

## 7. Upgrading to a Larger Cluster

One of the key features of this system is its ability to seamlessly upgrade to a larger cluster size while maintaining chronological order for both old and new job IDs. This is achieved by **adding an extra zero** to the worker ID padding, ensuring that new job IDs are always larger than old ones.

---

### 7.1 Why Upgrade?
- **Scalability**: As your system grows, you may need to support more workers.
- **Future-Proofing**: Upgrading to a larger cluster size ensures you can accommodate additional workers without disrupting existing operations.

---

### 7.2 How It Works
When upgrading from a smaller cluster size to a larger one:
1. **Add an Extra Zero**:
   - Auto add a `0` to the worker ID padding to match the new cluster size.
   - Example:
     - Upgrade from `cluster_size=100` (2-digit worker IDs) to `cluster_size=1000` (3-digit worker IDs).
     - Worker ID `05` becomes `005`.

2. **New Job IDs Are Larger**:
   - The extra zero ensures that new job IDs are numerically larger than old ones.
   - Example:
     - Old job ID: `25022512311472305` (2-digit worker ID).
     - New job ID: `250225123114723005` (3-digit worker ID).

3. **Chronological Order Preserved**:
   - Since the timestamp remains the same and the worker ID is padded with an extra zero, new job IDs will always sort after old ones in a database.

---

### 7.3 Example: Upgrading from `cluster_size=100` to `cluster_size=1000`
1. **Before Upgrade**:
   - `cluster_size=100`.
   - Worker ID: `42`.
   - Job ID format: `yyMMddHHmmssSSS + 42` → `25022512311472342`.

2. **After Upgrade**:
   - `cluster_size=1000`.
   - Worker ID: `42` becomes `042`.
   - Job ID format: `yyMMddHHmmssSSS + 042` → `250225123114723042`.

3. **Result**:
   - New job IDs (e.g., `250225123114723042`) are numerically larger than old ones (e.g., `25022512311472342`).
   - Chronological order is preserved when merging old and new job IDs.

---

### 7.4 Steps to Upgrade
1. **Update Configuration**:
   - All workers: Change the `cluster_size` to the new value (e.g., from `100` to `1000`).
   - Example:
     ```crystal
     options = SchedOptions.new(worker_id: 42, cluster_size: 1000)
     ```

2. **Deploy Changes**:
   - Roll out the updated configuration to all workers in the cluster.

3. **Verify Order**:
   - Test the system to ensure new job IDs are larger than old ones and that chronological order is preserved.

---

### 7.5 Benefits of This Approach
- **Backward Compatibility**: Old job IDs remain valid and sort correctly alongside new ones.
- **Seamless Transition**: No need to modify existing job IDs or databases.
- **Scalability**: Easily accommodate more workers by upgrading the cluster size.

---

### 7.6 Example Scenario
- **Initial Setup**:
  - `cluster_size=100`.
  - Worker ID: `7`.
  - Job ID: `25022512311472307`.

- **After Upgrade**:
  - `cluster_size=1000`.
  - Worker ID: `7` becomes `007`.
  - Job ID: `250225123114723007`.

- **Database Order**:
  - Old job ID: `25022512311472307`.
  - New job ID: `250225123114723007`.
  - Sorting: `25022512311472307` < `250225123114723007`.

---

## 8. Conclusion

This system provides a robust and scalable way to generate unique, chronologically ordered job IDs in a distributed environment. By following the guidelines in this manual, you can ensure smooth operation and avoid conflicts in your cluster.

Upgrading to a larger cluster size is straightforward and ensures that your system can scale without disrupting existing operations. By simply adding an extra zero to the worker ID padding, you can maintain chronological order and guarantee that new job IDs are always larger than old ones. This approach provides a seamless and future-proof solution for growing clusters.

For further assistance, refer to the code documentation or contact the development team.
