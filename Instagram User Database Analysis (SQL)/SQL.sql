use ig_clone;

-- Objective 

-- 02: per-user summary (posts, likes, comments) using CTEs and DISTINCT counts
WITH user_photos AS (
    SELECT user_id, COUNT(*) AS posts
    FROM photos
    GROUP BY user_id
),
user_likes AS (
    SELECT user_id, COUNT(DISTINCT photo_id) AS liked_photos
    FROM likes
    GROUP BY user_id
),
user_comments AS (
    SELECT user_id, COUNT(*) AS comments
    FROM comments
    GROUP BY user_id
)
SELECT uu.id AS user_id,
       uu.username,
       COALESCE(up.posts, 0) AS post_count,
       COALESCE(ul.liked_photos, 0) AS like_count,
       COALESCE(uc.comments, 0) AS comment_count
FROM users uu
LEFT JOIN user_photos up ON up.user_id = uu.id
LEFT JOIN user_likes ul ON ul.user_id = uu.id
LEFT JOIN user_comments uc ON uc.user_id = uu.id
ORDER BY uu.id;

-- 03: average tags per photo — alternative: use JOIN with aggregated derived table
SELECT AVG(tcount) AS avg_tags_per_post
FROM (
    SELECT pt.photo_id, COUNT(*) AS tcount
    FROM photo_tags pt
    GROUP BY pt.photo_id
) dt;

-- 04: top 10 users by engagement-per-post (likes+comments per post) using CTEs and window function
WITH photo_eng AS (
    SELECT p.user_id,
           COALESCE(SUM(lc.likes), 0) AS likes_total,
           COALESCE(SUM(cc.comments), 0) AS comments_total,
           COUNT(*) AS posts
    FROM photos p
    LEFT JOIN (
        SELECT photo_id, COUNT(*) AS likes FROM likes GROUP BY photo_id
    ) lc ON lc.photo_id = p.id
    LEFT JOIN (
        SELECT photo_id, COUNT(*) AS comments FROM comments GROUP BY photo_id
    ) cc ON cc.photo_id = p.id
    GROUP BY p.user_id
)
SELECT pe.user_id,
       (pe.likes_total + pe.comments_total) / GREATEST(pe.posts, 1) AS engagement_rate,
       RANK() OVER (ORDER BY (pe.likes_total + pe.comments_total) / GREATEST(pe.posts,1) DESC) AS rank_pos
FROM photo_eng pe
ORDER BY engagement_rate DESC
LIMIT 10;

-- 05: top followers and top followings (two separate queries, alternate aliasing)
-- most followers
SELECT followee_id AS user_id, COUNT(*) AS followers_count
FROM follows
GROUP BY followee_id
ORDER BY followers_count DESC
LIMIT 1;

-- most followings
SELECT follower_id AS user_id, COUNT(*) AS followings_count
FROM follows
GROUP BY follower_id
ORDER BY followings_count DESC
LIMIT 1;

-- 06: average engagement rate per user (percentage), rewritten to avoid joining likes and comments directly to photos rows
WITH per_photo_stats AS (
    SELECT p.id AS photo_id, p.user_id,
           COALESCE(lc.like_ct, 0) AS like_ct,
           COALESCE(cc.comment_ct, 0) AS comment_ct
    FROM photos p
    LEFT JOIN (SELECT photo_id, COUNT(*) AS like_ct FROM likes GROUP BY photo_id) lc ON lc.photo_id = p.id
    LEFT JOIN (SELECT photo_id, COUNT(*) AS comment_ct FROM comments GROUP BY photo_id) cc ON cc.photo_id = p.id
)
SELECT u.id AS user_id,
       u.username,
       ROUND( (SUM(per_photo_stats.like_ct + per_photo_stats.comment_ct) / NULLIF(COUNT(per_photo_stats.photo_id),0)) * 100, 2) AS avg_engagement_rate
FROM users u
JOIN per_photo_stats ON per_photo_stats.user_id = u.id
GROUP BY u.id
ORDER BY avg_engagement_rate DESC;

-- 07: users who never liked anything (anti-join style)
SELECT u.id AS user_id, u.username
FROM users u
WHERE NOT EXISTS (
    SELECT 1 FROM likes lk WHERE lk.user_id = u.id
);

-- 08: user totals: likes, comments, tags (different join order and DISTINCT where needed)
SELECT 
    u.id AS user_id,
    u.username,

    -- total likes received on user's photos
    COALESCE(( 
        SELECT COUNT(*) 
        FROM photos p 
        LEFT JOIN likes l ON l.photo_id = p.id
        WHERE p.user_id = u.id
    ), 0) AS total_likes,

    -- total comments made by the user
    COALESCE((
        SELECT COUNT(*) 
        FROM comments c
        WHERE c.user_id = u.id
    ), 0) AS total_comments,

    -- total tags used on user's photos
    COALESCE((
        SELECT COUNT(pt.tag_id)
        FROM photos p
        LEFT JOIN photo_tags pt ON pt.photo_id = p.id
        WHERE p.user_id = u.id
    ), 0) AS total_tags

FROM users u
ORDER BY u.id;

-- 09: top engaged users in last month using CTEs, alternate aggregation names
SELECT
    u.id AS user_id,
    u.username,
    HOUR(l.created_at) AS engagement_hour,
    COUNT(l.user_id) AS total_likes,
    COUNT(c.user_id) AS total_comments
FROM users u
LEFT JOIN likes l ON u.id = l.user_id
LEFT JOIN comments c ON u.id = c.user_id
GROUP BY u.id, HOUR(l.created_at)
ORDER BY total_likes DESC, total_comments DESC;

-- 10:  total number of likes, comments and photo tags for each user
SELECT 
  u.id   AS user_id,
  u.username,
  -- number of distinct photos of the user that received at least one like
  (SELECT COUNT(DISTINCT l.photo_id)
   FROM likes l
   JOIN photos p ON l.photo_id = p.id
   WHERE p.user_id = u.id) AS total_likes,

  -- total comments made by the user
  (SELECT COUNT(*) FROM comments c WHERE c.user_id = u.id) AS total_comments,

  -- number of distinct tags used on the user's photos
  (SELECT COUNT(DISTINCT pt.tag_id)
   FROM photo_tags pt
   JOIN photos p2 ON pt.photo_id = p2.id
   WHERE p2.user_id = u.id) AS total_tags
FROM users u;

-- 11: rank users based on their total engagement likes, comments, shares
SELECT 
    u.id AS user_id,
    u.username,
    COALESCE(l.total_likes, 0) + COALESCE(c.total_comments, 0) AS total_engagement
FROM users u
LEFT JOIN (
    SELECT user_id, COUNT(*) AS total_likes
    FROM likes
    GROUP BY user_id
) l ON u.id = l.user_id
LEFT JOIN (
    SELECT user_id, COUNT(*) AS total_comments
    FROM comments
    GROUP BY user_id
) c ON u.id = c.user_id
ORDER BY total_engagement DESC;

-- 12:  hashtags that have been used in posts with the highest average number of likes
WITH hashtag_avg_likes AS (
    SELECT 
        pt.tag_id,
        t.tag_name,
        AVG(l.like_count) AS avg_likes
    FROM photo_tags pt
    JOIN tags t ON pt.tag_id = t.id
    JOIN photos p ON pt.photo_id = p.id
    JOIN (
        SELECT photo_id, COUNT(*) AS like_count
        FROM likes
        GROUP BY photo_id
    ) l ON l.photo_id = p.id
    GROUP BY pt.tag_id, t.tag_name
)

SELECT 
    tag_name, 
    avg_likes
FROM hashtag_avg_likes
ORDER BY avg_likes DESC
LIMIT 10;

-- 13: mutual follows (alternate using JOIN)
SELECT f1.follower_id, f1.followee_id
FROM follows f1
JOIN follows f2
  ON f1.follower_id = f2.followee_id
 AND f1.followee_id = f2.follower_id;
 
 -- SUBJECTIVE — alternative-styled queries
 
-- 01: most loyal or valuable Based on user engagement and activity levels: compute likes per photo then aggregate by tag using JOIN and GROUP BY
SELECT
    u.id AS user_id,
    u.username,
    l.total_likes,
    c.total_comments,
    f.total_follows,
    (l.total_likes + c.total_comments + f.total_follows) AS total_engagement
FROM users u
CROSS JOIN (
    SELECT COUNT(*) AS total_likes
    FROM likes
) l
CROSS JOIN (
    SELECT COUNT(*) AS total_comments
    FROM comments
) c
CROSS JOIN (
    SELECT COUNT(*) AS total_follows
    FROM follows
) f
ORDER BY total_engagement DESC;

-- 02: users inactive for last 30 days (alternate NULL-handling and date comparisons)
SELECT 
    u.id,
    u.username
FROM users u
WHERE 
    COALESCE( (SELECT MAX(created_dat) FROM photos   WHERE user_id = u.id), '1970-01-01' ) 
        < NOW() - INTERVAL 30 DAY
AND COALESCE( (SELECT MAX(created_at)  FROM likes    WHERE user_id = u.id), '1970-01-01' ) 
        < NOW() - INTERVAL 30 DAY
AND COALESCE( (SELECT MAX(created_at)  FROM comments WHERE user_id = u.id), '1970-01-01' ) 
        < NOW() - INTERVAL 30 DAY;

-- 03: top 5 tags by usage + likes + comments (alternate aggregation aliases)
SELECT tg.id AS tag_id, tg.tag_name,
       COUNT(*) AS usage_count,
       SUM(CASE WHEN l.photo_id IS NOT NULL THEN 1 ELSE 0 END) AS likes_photo,
       SUM(CASE WHEN c.photo_id IS NOT NULL THEN 1 ELSE 0 END) AS comments_photo
FROM tags tg
LEFT JOIN photo_tags pt ON pt.tag_id = tg.id
LEFT JOIN likes l ON l.photo_id = pt.photo_id
LEFT JOIN comments c ON c.photo_id = pt.photo_id
GROUP BY tg.id, tg.tag_name
ORDER BY usage_count DESC
LIMIT 5;

-- 04: engagement by hour (alternate separation of like/comment times)
WITH like_hours AS (
    SELECT l.user_id, HOUR(l.created_at) AS hr, COUNT(*) AS likes_at_hour
    FROM likes l
    GROUP BY l.user_id, HOUR(l.created_at)
),
comment_hours AS (
    SELECT c.user_id, HOUR(c.created_at) AS hr, COUNT(*) AS comments_at_hour
    FROM comments c
    GROUP BY c.user_id, HOUR(c.created_at)
),
all_hours AS (
    -- union of hours where there was either a like or a comment
    SELECT user_id, hr FROM like_hours
    UNION
    SELECT user_id, hr FROM comment_hours
)
SELECT 
    u.id             AS user_id,
    u.username,
    ah.hr            AS engagement_hour,
    COALESCE(lh.likes_at_hour, 0)    AS total_likes,
    COALESCE(ch.comments_at_hour, 0) AS total_comments
FROM users u
LEFT JOIN all_hours ah ON ah.user_id = u.id
LEFT JOIN like_hours lh   ON lh.user_id = ah.user_id AND lh.hr = ah.hr
LEFT JOIN comment_hours ch ON ch.user_id = ah.user_id AND ch.hr = ah.hr
WHERE ah.hr IS NOT NULL        -- remove if you want users with no activity at all
GROUP BY u.id, u.username, ah.hr
ORDER BY total_likes DESC, total_comments DESC;

-- 05: combined metrics with followings_count (alternate join ordering and COALESCE safety)
WITH photo_metrics AS (
    SELECT p.user_id,
           SUM(COALESCE(lc.likes,0)) AS total_likes,
           SUM(COALESCE(cc.comments,0)) AS total_comments
    FROM photos p
    LEFT JOIN (SELECT photo_id, COUNT(*) AS likes FROM likes GROUP BY photo_id) lc ON lc.photo_id = p.id
    LEFT JOIN (SELECT photo_id, COUNT(*) AS comments FROM comments GROUP BY photo_id) cc ON cc.photo_id = p.id
    GROUP BY p.user_id
),
followings AS (
    SELECT follower_id AS user_id, COUNT(*) AS followings_count
    FROM follows
    GROUP BY follower_id
)
SELECT pm.user_id, u.username, pm.total_likes, pm.total_comments, COALESCE(f.followings_count, 0) AS followings_count
FROM photo_metrics pm
INNER JOIN users u ON u.id = pm.user_id
LEFT JOIN followings f ON f.user_id = pm.user_id
ORDER BY pm.total_likes DESC, pm.total_comments DESC, followings_count DESC;


-- 06: engagement-based segmentation (alternate thresholds and CASE ordering)
WITH engagement_totals AS (
    SELECT u.id AS user_id,
           u.username,
           COALESCE(SUM(l.likes_cnt),0) AS total_likes,
           COALESCE(SUM(c.comments_cnt),0) AS total_comments,
           COUNT(p.id) AS total_posts,
           COUNT(DISTINCT fv.follower_id) AS followers_count,
           COUNT(DISTINCT fv.followee_id) AS followings_count
    FROM users u
    LEFT JOIN photos p ON p.user_id = u.id
    LEFT JOIN (SELECT photo_id, COUNT(*) AS likes_cnt FROM likes GROUP BY photo_id) l ON l.photo_id = p.id
    LEFT JOIN (SELECT photo_id, COUNT(*) AS comments_cnt FROM comments GROUP BY photo_id) c ON c.photo_id = p.id
    LEFT JOIN follows fv ON fv.followee_id = u.id
    GROUP BY u.id
)
SELECT user_id, username,
       CASE
           WHEN total_likes > 50 AND total_comments > 50 AND total_posts > 5 THEN 'Engaged User'
           WHEN followers_count > 100 THEN 'Influencer'
           WHEN total_likes > 50 AND total_posts < 5 THEN 'Content Consumer'
           WHEN total_likes = 0 AND total_comments = 0 AND total_posts = 0 THEN 'Inactive User'
           ELSE 'Topic-Specific Enthusiast'
       END AS user_segment
FROM engagement_totals
ORDER BY user_segment;


-- 07: DDL for ad_campaigns (kept but slightly reformatted)
SELECT 
    id,
    campaign_name,
    impressions,
    clicks,
    conversions,
    cost,
    revenue,

    -- Click-through rate
    ROUND(clicks / NULLIF(impressions, 0), 4) AS ctr,

    -- Conversion rate (from clicks to conversions)
    ROUND(conversions / NULLIF(clicks, 0), 4) AS conversion_rate,

    -- Cost per click
    ROUND(cost / NULLIF(clicks, 0), 2) AS cpc,

    -- Cost per acquisition (cost per conversion)
    ROUND(cost / NULLIF(conversions, 0), 2) AS cpa,

    -- Return on ad spend
    ROUND(revenue / NULLIF(cost, 0), 2) AS roas

FROM ad_campaigns
ORDER BY roas DESC;

-- 08: per-user KPIs and filters (alternate subquery pattern)
SELECT *
FROM (
    SELECT 
        u.id AS user_id,
        u.username,

        (SELECT COUNT(*) FROM follows WHERE followee_id = u.id) AS total_followers,
        (SELECT COUNT(*) FROM photos WHERE user_id = u.id) AS total_photos_posted,

        COALESCE(
            (
                SELECT AVG(like_count)
                FROM (
                    SELECT COUNT(l.user_id) AS like_count
                    FROM likes l
                    JOIN photos p ON l.photo_id = p.id
                    WHERE p.user_id = u.id
                    GROUP BY p.id
                ) AS like_stats
            ), 0
        ) AS avg_likes_per_photo,

        COALESCE(
            (
                SELECT AVG(comment_count)
                FROM (
                    SELECT COUNT(c.id) AS comment_count
                    FROM comments c
                    JOIN photos p ON c.photo_id = p.id
                    WHERE p.user_id = u.id
                    GROUP BY p.id
                ) AS comment_stats
            ), 0
        ) AS avg_comments_per_photo,

        COALESCE(
            (
                -- use photos.created_dat (your schema) for last photo time
                SELECT MAX(p.created_dat) 
                FROM photos p 
                WHERE p.user_id = u.id
            ),
            u.created_at
        ) AS last_activity_date

    FROM users u
) AS t
WHERE t.total_followers > 50
  AND t.total_photos_posted > 5
  AND t.avg_likes_per_photo > 30
ORDER BY t.avg_likes_per_photo DESC;

-- 10: rename Engagement_Type values in User_Interactions (kept identical but safe)
UPDATE user_interactions
SET engagement_type = 'Heart'
WHERE engagement_type = 'Like';


