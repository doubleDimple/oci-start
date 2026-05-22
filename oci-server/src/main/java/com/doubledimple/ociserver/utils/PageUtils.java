package com.doubledimple.ociserver.utils;

import com.doubledimple.ociserver.pojo.request.BaseRequest;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.data.jpa.domain.Specification;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;
import org.springframework.util.StringUtils;

import java.util.ArrayList;
import java.util.List;

public class PageUtils {

    /**
     * 将List数据转换为Spring Data Page对象
     * @param allData 所有数据
     * @param page 页码（从0开始）
     * @param size 每页大小
     * @return Page对象
     */
    public static <T> Page<T> createPage(List<T> allData, int page, int size) {
        if (allData == null) {
            allData = new ArrayList<>();
        }

        // 创建Pageable对象
        Pageable pageable = PageRequest.of(page, size);

        // 计算分页数据
        int startIndex = page * size;
        int endIndex = Math.min(startIndex + size, allData.size());

        List<T> pageContent;
        if (startIndex < allData.size() && startIndex >= 0) {
            pageContent = allData.subList(startIndex, endIndex);
        } else {
            pageContent = new ArrayList<>();
        }

        // 创建PageImpl对象
        return new PageImpl<>(pageContent, pageable, allData.size());
    }

    /**
     * 创建空分页对象
     * @param page 页码
     * @param size 每页大小
     * @return 空的Page对象
     */
    public static <T> Page<T> createEmptyPage(int page, int size) {
        Pageable pageable = PageRequest.of(page, size);
        return new PageImpl<>(new ArrayList<>(), pageable, 0L);
    }


    /**
     * 构建分页参数
     */
    public static Pageable buildPageable(BaseRequest request) {
        return buildPageable(request, "createTime");
    }

    /**
     * 构建分页参数，指定默认排序字段
     */
    public static Pageable buildPageable(BaseRequest request, String defaultSortField) {
        // 构建分页参数
        int page = Math.max(0, request.getPageNum() - 1); // 页码从0开始
        int size = request.getPageSize() > 0 ? request.getPageSize() : 10; // 默认每页10条

        // 构建排序
        Sort sort = Sort.by(Sort.Direction.DESC, defaultSortField); // 默认排序
        if (StringUtils.hasText(request.getSort())) {
            Sort.Direction direction = "asc".equalsIgnoreCase(request.getOrder())
                    ? Sort.Direction.ASC : Sort.Direction.DESC;
            sort = Sort.by(direction, request.getSort());
        }

        return PageRequest.of(page, size, sort);
    }

    /**
     * 构建动态查询条件
     */
    public static <T> Page<T> findWithSpec(JpaSpecificationExecutor<T> repository,
                                           BaseRequest request,
                                           Specification<T> spec) {
        return findWithSpec(repository, request, spec, "createTime");
    }

    /**
     * 构建动态查询条件，指定默认排序字段
     */
    public static <T> Page<T> findWithSpec(JpaSpecificationExecutor<T> repository,
                                           BaseRequest request,
                                           Specification<T> spec,
                                           String defaultSortField) {
        Pageable pageable = buildPageable(request, defaultSortField);
        return repository.findAll(spec, pageable);
    }
}
