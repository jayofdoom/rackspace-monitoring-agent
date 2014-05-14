--[[
Copyright 2014 Rackspace

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS-IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
--]]
local Scheduler = require('/schedule').Scheduler
local ConnectionStream = require("/base/client/connection_stream").ConnectionStream

local logging = require('logging')
local loggingUtil = require('/base/util/logging')
local fmt = require('string').format
local utils = require('utils')

local VirgoConnectionStream = ConnectionStream:extend()
function VirgoConnectionStream:initialize(id, token, guid, upgradeEnabled, options, types)
  ConnectionStream.initialize(self, id, token, guid, upgradeEnabled, options, types)
  self._log = loggingUtil.makeLogger('stream')
  self._scheduler = Scheduler:new()
  self._scheduler:on('check.completed', function(check, checkResult)
    self:_sendMetrics(check, checkResult)
  end)
  self._scheduler:on('check.deleted', function(check)
    self._log(logging.INFO, fmt('Deleted Check (id=%s, iid=%s)', 
      check.id, check:getInternalId()))
  end)
  self._scheduler:on('check.created', function(check)
    self._log(logging.INFO, fmt('Created Check (id=%s, iid=%s)', 
      check.id, check:getInternalId()))
  end)
  self._scheduler:on('check.modified', function(check)
    self._log(logging.INFO, fmt('Modified Check (id=%s, iid=%s)', 
      check.id, check:getInternalId()))
  end)
end

function VirgoConnectionStream:_createConnection(options)
  local client = ConnectionStream._createConnection(self, options)
  client:setScheduler(self._scheduler)
  return client
end

function VirgoConnectionStream:_sendMetrics(check, checkResult)
  local client = self:getClient()
  if client then
    client.protocol:request('check_metrics.post', check, checkResult)
  end
end

return VirgoConnectionStream
