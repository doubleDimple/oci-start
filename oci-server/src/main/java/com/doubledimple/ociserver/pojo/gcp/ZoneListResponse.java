package com.doubledimple.ociserver.pojo.gcp;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.Data;

import java.util.ArrayList;
import java.util.List;

/**
 * @version 1.0.0
 * @ClassName ZoneListResponse
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-06-22 14:39
 */
@JsonIgnoreProperties(ignoreUnknown = true)
@Data
public class ZoneListResponse {

    @JsonProperty("items")
    private List<ZoneInfo> items = new ArrayList<>();
}
