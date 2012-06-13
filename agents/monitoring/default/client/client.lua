--[[
Copyright 2012 Rackspace

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

local Timer = require('uv').Timer
local consts = require('../util/constants')
local tls = require('tls')
local timer = require('timer')
local Error = require('core').Error
local Object = require('core').Object
local Emitter = require('core').Emitter
local check = require('../check')
local logging = require('logging')
local misc = require('../util/misc')
local loggingUtil = require ('../util/logging')
local AgentProtocolConnection = require('../protocol/connection')
local table = require('table')

local fmt = require('string').format

local AgentClient = Emitter:extend()

local HEARTBEAT_INTERVAL = 5 * 60 * 1000 -- ms

function AgentClient:initialize(options, scheduler)

  self.protocol = nil
  self._datacenter = options.datacenter
  self._id = options.id
  self._token = options.token
  self._target = 'endpoint'
  self._host = options.host
  self._port = options.port
  self._timeout = options.timeout or 5000

  self._scheduler = scheduler

  self._heartbeat_interval = nil
  self._sent_heartbeat_count = 0
  self._got_pong_count = 0
  self._latency = nil

  self._log = loggingUtil.makeLogger(fmt('%s:%s', self._host, self._port))
end

function AgentClient:getDatacenter()
  return self._datacenter
end

function AgentClient:scheduleManifest(manifest)
  local checks = self:_createChecks(manifest)
  self._scheduler:rebuild(checks, function()
    self._log(logging.DEBUG, 'Reloaded manifest')
    self._scheduler:start()
  end)
end

function AgentClient:_createChecks(manifest)
  local checks = {}

  for i, _ in ipairs(manifest.checks) do
    local check = check.create(manifest.checks[i])
    if check then
      self._log(logging.INFO, 'Created Check: ' .. check:toString())
      table.insert(checks, check)
    end
  end

  return checks
end

function AgentClient:log(priority, ...)
  self._log(priority, unpack({...}))
end

function AgentClient:_socketTimeout()
  return misc.calcJitter(HEARTBEAT_INTERVAL, consts.SOCKET_TIMEOUT)
end

function AgentClient:connect()
  -- Create connection timeout
  self._log(logging.DEBUG, 'Connecting...')
  self._sock = tls.connect(self._port, self._host, {}, function(err, cleartext)
    -- Log
    self._log(logging.INFO, 'Connected')

    -- setup protocol
    self.protocol = AgentProtocolConnection:new(self._log, self._id, self._token, cleartext)
    self.protocol:on('error', function(err)
      self:emit(err)
    end)
    -- response to messages
    self.protocol:on('message', function(msg)
      self:emit('message', msg, self)
      self.protocol:execute(msg)
    end)

    -- begin handshake
    self.protocol:startHandshake(function(err, msg)
      if err then
        self:emit('error', err)
      else
        self._heartbeat_interval = msg.result.heartbeat_interval
        self:emit('handshake_success')
      end
    end)
  end)
  self._log(logging.DEBUG, fmt('Using timeout %sms', self:_socketTimeout()))
  self._sock.socket:setTimeout(self:_socketTimeout(), function()
    self:emit('timeout')
  end)
  self._sock:on('error', function(err)
    self._log(logging.ERROR, fmt('Failed to connect: %s', err.message))
    self:emit('error', err)
  end)
  self._sock:on('end', function()
    self:emit('end')
  end)
end

function AgentClient:getLatency()
  return self._latency
end

function AgentClient:startHeartbeatInterval()
  function startInterval(this)
    local timeout = misc.calcJitter(self._heartbeat_interval, consts.HEARTBEAT_INTERVAL_JITTER)

    this._log(logging.DEBUG, fmt('Starting heartbeat interval, interval=%dms', this._heartbeat_interval))

    this._heartbeatTimeout = timer.setTimeout(timeout, function()
      local send_timestamp = Timer.now()

      this._log(logging.DEBUG, fmt('Sending heartbeat (timestamp=%d,sent_heartbeat_count=%d,got_pong_count=%d)',
                                    send_timestamp, this._sent_heartbeat_count, this._got_pong_count))
      this._sent_heartbeat_count = this._sent_heartbeat_count + 1
      this.protocol:request('heartbeat.post', send_timestamp, function(err, msg)
        if err then
          this._log(logging.DEBUG, 'Got an error while sending heartbeat: ' .. tostring(err))
          return
        end

        this._latency = Timer.now() - send_timestamp

        if msg.result.timestamp then
          this._got_pong_count = this._got_pong_count + 1
          this._log(logging.DEBUG, fmt('Got pong (latency=%f,sent_heartbeat_count=%d,got_pong_count=%d)',
                                       this._latency, this._sent_heartbeat_count, this._got_pong_count))
        else
          this._log(logging.DEBUG, 'Got invalid pong response')
        end

        startInterval(this)
      end)
    end)
   end

   startInterval(self)
end

function AgentClient:clearHeartbeatInterval()
  if self._heartbeatTimeout then
    self._log(logging.DEBUG, 'Clearing heartbeat interval')
    timer.clearTimer(self._heartbeatTimeout)
    self._heartbeatTimeout = nil
  end
end

function AgentClient:destroy()
  self:clearHeartbeatInterval()

  if self._sock then
    self._log(logging.DEBUG, 'Closing socket')
    self._sock:destroy()
    self._sock = nil
  end
end

local exports = {}
exports.AgentClient = AgentClient
return exports