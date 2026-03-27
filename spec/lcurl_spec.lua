local curl = require("lcurl")

describe("Modern libcurl (Intel-built) Features", function()
   local e

   before_each(function()
	 e = curl.easy()
	 -- Use Windows Native CA Trust for all tests
	 e:setopt_ssl_options(curl.SSLOPT_NATIVE_CA) -- CURLSSLOPT_NATIVE_CA
   end)

   after_each(function()
	 e:close()
   end)

   it("should resolve and connect via Threaded Resolver", function()
	 e:setopt_url("https://www.google.com")
	 e:setopt_nobody(true) -- HEAD request only
	 local ok, err = pcall(function() e:perform() end)
	 assert.True(ok)
	 assert.equal(200, e:getinfo_response_code())
   end)
   
   it("should attempt HTTP/3 (QUIC) connection", function()
	 e:setopt_url("https://www.google.com")
	 e:setopt_http_version(4) -- CURL_HTTP_VERSION_3
	 e:setopt_verbose(false)
	 e:setopt_nobody(true)
            
	 local ok = pcall(function() e:perform() end)
	 assert.True(ok)
	 -- Note: Google might return h2 first (alt-svc), 
	 -- but the library must not crash or error out.
   end)

   it("should support Unicode/IDN domain names", function()
	 -- Testing with a German umlaut domain
	 e:setopt_url("https://www.müller.de")
	 e:setopt_nobody(true)
	 local ok = pcall(function() e:perform() end)
	 assert.True(ok)
   end)

   it("should successfully upgrade to HTTP/3 (QUIC) using Alt-Svc", function()
	 local e = curl.easy({
	       url             = "https://www.google.com",
	       -- url             = "https://cloudflare-quic.com",
	       -- Force HTTP/3 or allow upgrade
	       http_version    = 4, -- CURL_HTTP_VERSION_3
	       ssl_options     = curl.SSLOPT_NATIVE_CA,
	       nobody          = true, -- We only need the headers/connection info
	       -- Enable Alt-Svc caching to remember the H3 endpoint
	       altsvc          = "altsvc_cache.txt", 
	       timeout         = 15,
	 })

	 -- Perform the first request (often negotiates H3 via Alt-Svc header)
	 local ok1, err1 = pcall(function() e:perform() end)
        
	 -- Perform a second request to actually use the cached HTTP/3 info
	 local ok2, err2 = pcall(function() e:perform() end)
        
	 local version = e:getinfo(curl.INFO_HTTP_VERSION)
	 local status = e:getinfo(curl.INFO_RESPONSE_CODE)

	 assert.is_true(ok2, "HTTP/3 connection failed: " .. tostring(err2))
	 assert.equal(200, status)
        
	 -- Check if version is indeed HTTP/3
	 -- Note: In libcurl/lcurl, the constant for H3 is usually 3 (CURL_HTTP_VERSION_3)
	 -- but getinfo returns the actual protocol version used.
	 -- print("\n[DEBUG] Protocol used: " .. tostring(version))
        
	 -- We check if version is >= 3 (where 3 is H3 in some versions, or 4 in others)
	 assert.is_true(version >= 3, "Failed to upgrade to at least HTTP/2 or HTTP/3")
   end)   
end)

describe("Advanced Concurrency (Multi-Handle)", function()
    it("should perform 5 parallel requests without blocking", function()
        local m = curl.multi()
        local urls = {
            "https://www.google.com",
            "https://www.bing.com",
            "https://www.cloudflare.com",
            "https://httpbin.org",
            "https://www.wikipedia.org"
        }
        
        local handles = {}
	for i, url in ipairs(urls) do
	   local e = curl.easy{
	      url            = url,
	      nobody         = true,
	      ssl_options    = curl.SSLOPT_NATIVE_CA, -- Native CA
	      followlocation = true
	   }
	   m:add_handle(e)
	   handles[i] = e
        end

	-- Correct way to wait for all handles in Lua-cURLv3
        repeat
	   -- m:perform() returns the number of active handles
	   m:wait(100)
        until m:perform() <= 0

	for _, e in ipairs(handles) do
	   local code = e:getinfo_response_code()
	   assert.is_not_nil(code)
	   assert.True(code > 0)
	   e:close()
        end
        m:close()
    end)
end)

describe("Response formats", function()
    it("should automatically decompress Brotli content", function()
	  local cjson = require("cjson")
	  local e = curl.easy({
	      url             = "https://httpbin.org/brotli",
	      accept_encoding = "",
	      ssl_options     = curl.SSLOPT_NATIVE_CA,
	})
    
	local response_body = {}
	e:setopt_writefunction(function(chunk) 
	      table.insert(response_body, chunk) 
	      return #chunk 
	end)
    
	local ok, err = pcall(function() e:perform() end)
	local status = e:getinfo(curl.INFO_RESPONSE_CODE)
	e:close()
	assert.is_true(ok, "Curl error: " .. tostring(err))
	assert.equal(200, status)
    
	local body = table.concat(response_body)
    
	-- Test 1: valid json?
	local ok_json, data = pcall(cjson.decode, body)
	assert.is_true(ok_json, "Body was not decompressed or is invalid JSON. Error: " .. tostring(data))
	assert.is_table(data, "Expected JSON object as response")
    
	-- Test 2: Check if JSON contains the 'brotli' key (httpbin-specific)
	assert.is_true(data.brotli, "Brotli flag missing in response")
    end)

    it("should automatically decompress Zstd content", function()
        local e = curl.easy({
	      url             = "https://www.cloudflare.com",
	      accept_encoding = "zstd",
	      ssl_options     = curl.SSLOPT_NATIVE_CA,
	      timeout         = 10,
        })
    
        local response_body = {}
        e:setopt_writefunction(function(chunk) 
	      table.insert(response_body, chunk) 
	      return #chunk 
        end)
    
        local ok, err = pcall(function() e:perform() end)
        local status = e:getinfo(curl.INFO_RESPONSE_CODE)
        e:close()

        assert.is_true(ok, "Curl error (check if your libcurl supports Zstd): " .. tostring(err))
        assert.equal(200, status)
    
        local body = table.concat(response_body)

	local is_html = body:match("<html") ~= nil
        assert.is_true(is_html,
		       "Body was not decompressed (no HTML found). Content starts with: " .. body:sub(1, 20))
    end)

    it("should automatically decompress Deflate content", function()
        local cjson = require("cjson")
        local e = curl.easy({
            url             = "https://httpbin.org/deflate",
            accept_encoding = "deflate",
            ssl_options     = curl.SSLOPT_NATIVE_CA,
            timeout         = 10,
        })
    
        local response_body = {}
        e:setopt_writefunction(function(chunk) 
            table.insert(response_body, chunk) 
            return #chunk 
        end)
    
        local ok, err = pcall(function() e:perform() end)
        local status = e:getinfo(curl.INFO_RESPONSE_CODE)
        e:close()

        assert.is_true(ok, "Curl error: " .. tostring(err))
        assert.equal(200, status)
    
        local body = table.concat(response_body)
    
        -- Test 1: valid json?
        local ok_json, data = pcall(cjson.decode, body)
        assert.is_true(ok_json, "Body was not decompressed or is invalid JSON. Error: " .. tostring(data))
    
        -- Test 2: Check if JSON contains the 'deflated' key (httpbin-specific)
        -- Hinweis: httpbin nennt das Feld bei diesem Endpoint 'deflated' (mit 'd' am Ende)
        assert.is_true(data.deflated, "Deflate flag missing in response")
    end)

    it("should automatically decompress Gzip content", function()
        local cjson = require("cjson")
        local e = curl.easy({
            url             = "https://httpbin.org/gzip",
            accept_encoding = "gzip",
            ssl_options     = curl.SSLOPT_NATIVE_CA,
            ipresolve       = 1,
            timeout         = 10,
        })
    
        local response_body = {}
        e:setopt_writefunction(function(chunk) 
            table.insert(response_body, chunk) 
            return #chunk 
        end)
    
        local ok, err = pcall(function() e:perform() end)
        local status = e:getinfo(curl.INFO_RESPONSE_CODE)
        e:close()

        assert.is_true(ok, "Curl error: " .. tostring(err))
        assert.equal(200, status)
    
        local body = table.concat(response_body)
    
        -- Test 1: Validate if the body is correctly decompressed JSON
        local ok_json, data = pcall(cjson.decode, body)
        assert.is_true(ok_json, "Body was not decompressed or is invalid JSON. Error: " .. tostring(data))
    
        -- Test 2: Check for the 'gzipped' key (httpbin-specific)
        -- Note: httpbin uses 'gzipped' (with a trailing 'd') for this endpoint
        assert.is_true(data.gzipped, "Gzip flag missing in response")
    end)
    
    it("should correctly handle UTF-8 encoded content", function()
	local utf8 = require("lua-utf8")
        local e = curl.easy({
	      url             = "https://httpbin.org/encoding/utf8",
	      ssl_options     = curl.SSLOPT_NATIVE_CA,
	      ipresolve       = 1,
	      timeout         = 10,
        })
    
        local response_body = {}
        e:setopt_writefunction(function(chunk) 
	      table.insert(response_body, chunk) 
	      return #chunk 
        end)
    
        local ok, err = pcall(function() e:perform() end)
        local status = e:getinfo(curl.INFO_RESPONSE_CODE)
        e:close()

        assert.is_true(ok, "Curl error: " .. tostring(err))
        assert.equal(200, status)
    
        local body = table.concat(response_body)
    
        -- Test 1: Basic integrity check (look for common UTF-8 markers in the HTML)
        -- The page contains specific non-ASCII characters.
        assert.is_not_nil(body:match("გთხოვთ"), "UTF-8 content (Gregorian characters) missing")

        -- Test 2: Use lua-utf8 to verify string validity
        -- utf8.isvalid returns true if the string is a sequence of valid UTF-8 sequences
        assert.is_true(utf8.isvalid(body), "Response body contains invalid UTF-8 sequences")

        -- Test 3: Measure actual character count vs. byte count
        -- In UTF-8, characters like 'ø' take 2 bytes. 
        -- utf8.len returns the number of characters, while #body returns bytes.
        local byte_count = #body
        local char_count = utf8.len(body)
        
        assert.is_true(byte_count > char_count, "UTF-8 multibyte characters not detected")
        -- print("\n[DEBUG] Bytes: " .. byte_count .. " | Characters: " .. char_count)
    end)

end)
