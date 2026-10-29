package com.doubledimple.ociserver.pojo.response;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;
import java.util.ArrayList;
import java.util.List;

/** Aggregate values only: never serialize account credentials or audit payloads. */
@Data
public class BusinessOverview {
    private int days;
    private String startDate;
    private String endDate;
    private String timeZone;
    private long generatedAt;
    private long accounts;
    private long instances;
    private long regions;
    private long ocpus;
    private long memoryGiB;
    private long bootVolumeGiB;
    private long knownCpuInstances;
    private long knownMemoryInstances;
    private long knownVolumeInstances;
    private List<Bucket> accountStates = new ArrayList<>();
    private List<Bucket> instanceStates = new ArrayList<>();
    private List<Bucket> architectures = new ArrayList<>();
    private List<Bucket> monitoring = new ArrayList<>();
    private List<Bucket> regionRanking = new ArrayList<>();
    private List<Bucket> tenantRanking = new ArrayList<>();
    private Activity operations;
    private Activity email;
    private DashboardStats launch;

    @Data @NoArgsConstructor @AllArgsConstructor
    public static class Bucket {
        private String key;
        private String label;
        private long count;
    }

    @Data
    public static class Activity {
        private long total;
        private long success;
        private long failed;
        private long unknown;
        private List<Day> daily = new ArrayList<>();
    }

    @Data @NoArgsConstructor @AllArgsConstructor
    public static class Day {
        private String date;
        private long success;
        private long failed;
        private long unknown;
    }
}
