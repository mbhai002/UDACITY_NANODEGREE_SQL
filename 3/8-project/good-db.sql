-- create users table
CREATE TABLE "users" (
  "id" SERIAL PRIMARY KEY,
  "username" VARCHAR(25) NOT NULL,
  "last_login_at" TIMESTAMP DEFAULT CURRENT_TIMESTAMP 
  );

-- Ensure usernames are unique
ALTER TABLE "users" ADD CONSTRAINT "username_unique"
    UNIQUE ("username");

-- ensure username can’t be empty\blank.
ALTER TABLE "users"
ADD CONSTRAINT "chk_username_text" CHECK (trim("username") <> '');

CREATE TABLE topics (
    id SERIAL PRIMARY KEY,
    name VARCHAR(30) NOT NULL,
    description VARCHAR(500)
    
);

-- Ensure topic names are unique
ALTER TABLE "topics" 
ADD CONSTRAINT "unique_topic_name" UNIQUE ("name");

-- Ensure topic names cannot be empty (NOT NULL)
ALTER TABLE "topics"
ADD CONSTRAINT "chk_topic_name" CHECK (trim("name") <> '');


CREATE TABLE posts (
    id SERIAL PRIMARY KEY,
    topic_id INT ,
    user_id INT,
    title VARCHAR(100) NOT NULL,
    url VARCHAR(400) ,
    text_content TEXT ,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- A comment’s text content can’t be empty.
ALTER TABLE "posts"
ADD CONSTRAINT "chk_title" CHECK (trim("text_content") <> '');


-- Ensure posts contain either a URL or text content, but not both
ALTER TABLE "posts" 
ADD CONSTRAINT "chk_url_or_text" CHECK (
    (url IS NOT NULL AND "text_content" IS NULL) OR 
    (url IS NULL AND "text_content" IS NOT NULL)
);

-- Automatically delete posts if the topic is deleted
ALTER TABLE "posts" 
ADD CONSTRAINT "fk_posts_topic" FOREIGN KEY ("topic_id") 
REFERENCES "topics"("id") ON DELETE CASCADE;

-- If a user is deleted, keep the post but dissociate it from the user
ALTER TABLE posts 
ADD CONSTRAINT "fk_posts_user" FOREIGN KEY ("user_id") 
REFERENCES "users"("id") ON DELETE SET NULL;


CREATE TABLE comments (
    id SERIAL PRIMARY KEY,
    user_id INT,        -- ID of the user who made the comment
    post_id INT,       -- ID of the post to which the comment belongs
    parent_comment_id INT ,  -- ID of the parent comment (NULL for top-level comments)
    text_content, TEXT NOT NULL -- The comment text (cannot be empty)
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- A comment’s text content can’t be empty.
ALTER TABLE "comments"
ADD CONSTRAINT "chk_comment_text" CHECK (trim("text_content") <> '');

-- If a post gets deleted, all comments associated with it should be automatically deleted too.
ALTER TABLE "comments" ADD CONSTRAINT "fk_comments_post" 
FOREIGN KEY ("post_id") REFERENCES "posts"(id) ON DELETE CASCADE;

-- If the user who created the comment gets deleted, then the comment will remain, but it will become dissociated from that user.
ALTER TABLE "comments" ADD CONSTRAINT "fk_comments_user" 
FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE SET NULL;

-- If a comment gets deleted, then all its descendants in the thread structure should be automatically deleted too.

ALTER TABLE "comments" ADD CONSTRAINT "fk_comments_parent" 
FOREIGN KEY ("parent_comment_id") REFERENCES "comments"("id") ON DELETE CASCADE;



CREATE TABLE votes (
    id SERIAL PRIMARY KEY,
    user_id INT,       -- ID of the user who voted 
    post_id INT ,  -- ID of the post being voted on
    vote_value SMALLINT NOT NULL  -- Vote value: 1 or -1 
);

-- you can store the (up/down) value of the vote as the values 1 and -1 respectively
ALTER TABLE "votes" 
ADD CONSTRAINT "chk_vote_value" CHECK ("vote_value" IN (-1, 1));

-- given user can only vote once
ALTER TABLE "votes" 
ADD CONSTRAINT "unique_user_post_vote" UNIQUE ("user_id", "post_id");

-- If the user who cast a vote gets deleted, then all their votes will remain, but will become dissociated from the user.
ALTER TABLE "votes"  ADD CONSTRAINT "fk_votes_user"
FOREIGN KEY ("user_id") REFERENCES "users"(id) ON DELETE SET NULL;

-- If a post gets deleted, then all the votes for that post should be automatically deleted too.

ALTER TABLE "votes"  ADD CONSTRAINT "fk_votes_post" 
FOREIGN KEY ("post_id") REFERENCES "posts"(id) ON DELETE CASCADE;


-- Indexes to improve join performance on foreign keys:
CREATE INDEX idx_posts_topic_id ON posts(topic_id);
CREATE INDEX idx_posts_user_id  ON posts(user_id);


-- Indexes for quick lookups on foreign key columns:
CREATE INDEX idx_comments_post_id           ON comments(post_id);
CREATE INDEX idx_comments_parent_comment_id ON comments(parent_comment_id);
CREATE INDEX idx_comments_user_id           ON comments(user_id);


-- Indexes for performance:
CREATE INDEX idx_votes_post_id ON votes(post_id);
CREATE INDEX idx_votes_user_id ON votes(user_id);


INSERT INTO users(username)
SELECT DISTINCT trim(username)
FROM (
  SELECT username
    FROM bad_posts
  UNION
  SELECT username
    FROM bad_comments
  UNION
  -- Unwind comma-separated upvotes
  SELECT regexp_split_to_table(upvotes, ',') AS username
    FROM bad_posts
    WHERE upvotes IS NOT NULL
  UNION
  -- Unwind comma-separated downvotes
  SELECT regexp_split_to_table(downvotes, ',') AS username
    FROM bad_posts
    WHERE downvotes IS NOT NULL
) AS all_users
WHERE trim(username) <> '';



INSERT INTO topics(name, description)
SELECT DISTINCT trim(topic) AS name,
       '' AS description
FROM bad_posts
WHERE topic IS NOT NULL AND trim(topic) <> '';


INSERT INTO posts(id, topic_id, user_id, title, url, text_content)
SELECT b.id,
       t.id,
       u.id,
       left(b.title,100),
       b.url,
       b.text_content
FROM bad_posts b
JOIN topics t ON t.name = trim(b.topic)
JOIN users u ON u.username = trim(b.username);


INSERT INTO comments(user_id, post_id, parent_comment_id, text_content)
SELECT u.id,
       p.id,
       NULL,               -- No parent since legacy comments are not threaded
       bc.text_content
       
FROM bad_comments bc
JOIN posts p ON p.id = bc.post_id
JOIN users u ON u.username = trim(bc.username);


INSERT INTO votes(user_id, post_id, vote_value)
SELECT u.id,
       b.id,
       1 AS vote_value
       
FROM bad_posts b
CROSS JOIN LATERAL regexp_split_to_table(b.upvotes, ',') AS vote_username
JOIN users u ON u.username = trim(vote_username)
WHERE b.upvotes IS NOT NULL AND trim(b.upvotes) <> '';


INSERT INTO votes(user_id, post_id, vote_value)
SELECT u.id,
       b.id,
       -1 AS vote_value
FROM bad_posts b
CROSS JOIN LATERAL regexp_split_to_table(b.downvotes, ',') AS vote_username
JOIN users u ON u.username = trim(vote_username)
WHERE b.downvotes IS NOT NULL AND trim(b.downvotes) <> '';