package com.doubledimple.ocicommon.utils;

import lombok.extern.slf4j.Slf4j;

import java.util.List;

@Slf4j
public class PagingUtils {
    /**
     *
     * @param queryFunc 分页查询函数，用于获取特定页码的数据。
     * @param executor 执行器，用于处理查询到的数据。
     * @param maxPageNum 最大页码数，限制查询的范围。
     */
    public static <T> void executePagedWithoutThrowing(PageQueryFunction<T> queryFunc,
                                        PageExecutor<T> executor,int maxPageNum) {
        executeWithPagination(queryFunc, executor, maxPageNum, true);
    }
    /**
     * 以分页方式执行查询操作，并不捕获执行过程中的异常。
     * 此方法适用于查询操作和执行操作可能抛出异常的场景，中断程序。
     *
     * @param queryFunc 分页查询函数，用于获取特定页码的数据。
     * @param executor 执行器，用于处理查询到的数据。
     * @param maxPageNum 最大页码数，限制查询的范围。
     */
    public static <T> void executePaged(PageQueryFunction<T> queryFunc, PageExecutor<T> executor,int maxPageNum) {
        executeWithPagination(queryFunc, executor, maxPageNum, false);
    }
    private static <T> void executeWithPagination(PageQueryFunction<T> queryFunc, PageExecutor<T> executor, int maxPageNum, boolean handleException) {
        int pageNum = 1;
        int pageSize = 100;
        List<T> dataList;
        while ((dataList = queryFunc.apply(pageNum++, pageSize)) != null && !dataList.isEmpty() && pageNum <= maxPageNum) {
            for (T item : dataList) {
                if (handleException) {
                    try {
                        executor.execute(item);
                    }catch (Exception e){
                        log.warn("分页执行时发生错误: {}", e.getMessage(), e);
                    }
                } else {
                    executor.execute(item);
                }
            }
        }
    }
    @FunctionalInterface
    public interface PageQueryFunction<T> {
        List<T> apply(int pageNum, int pageSize);
    }
    @FunctionalInterface
    public interface PageExecutor<T> {
        void execute(T t);
    }
}
