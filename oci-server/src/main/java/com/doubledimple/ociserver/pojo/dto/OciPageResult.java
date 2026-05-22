package com.doubledimple.ociserver.pojo.dto;

import lombok.AllArgsConstructor;
import lombok.Data;

import java.util.List;

/**
 * @version 1.0.0
 * @ClassName OciPageResult
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-10-31 11:25
 */
@Data
@AllArgsConstructor
public class OciPageResult<T> {

    private List<T> data;
    private String nextPageToken; // 下一页标识
}
