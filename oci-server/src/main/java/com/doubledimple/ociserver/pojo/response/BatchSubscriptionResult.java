package com.doubledimple.ociserver.pojo.response;

import lombok.Data;

import java.util.ArrayList;
import java.util.List;

/**
 *
 */
@Data
public class BatchSubscriptionResult {

    private List<RegionSubscriptionResult> successResults = new ArrayList<>();
    private List<RegionSubscriptionResult> failedResults = new ArrayList<>();
    private int totalCount;
    private int successCount;
    private int failedCount;

    public void addResult(RegionSubscriptionResult result) {
        if (result.isSuccess()) {
            successResults.add(result);
            successCount++;
        } else {
            failedResults.add(result);
            failedCount++;
        }
        totalCount++;
    }

    // Getters
    public List<RegionSubscriptionResult> getSuccessResults() { return successResults; }
    public List<RegionSubscriptionResult> getFailedResults() { return failedResults; }
    public int getTotalCount() { return totalCount; }
    public int getSuccessCount() { return successCount; }
    public int getFailedCount() { return failedCount; }
    public boolean isAllSuccess() { return failedCount == 0; }
    public boolean hasFailures() { return failedCount > 0; }

    @Override
    public String toString() {
        return String.format("BatchSubscriptionResult{total=%d, success=%d, failed=%d}",
                totalCount, successCount, failedCount);
    }
}
