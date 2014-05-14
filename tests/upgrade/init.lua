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
local exec = require('virgo_exec')
local string = require('string')
local upgrade = require('/base/client/upgrade')

local exports = {}

local function createOptions(bExe, myVersion)
  return {
    ['b'] = { ['exe'] = bExe },
    my_version = myVersion,
    pretend = true
  }
end

exports['test_virgo_upgrade_1'] = function(test, asserts)
  local options = createOptions('tests/upgrade/exe/0001.sh', '0.2.0-24')
  upgrade.attempt(options, function(err, status)
    asserts.ok(not err)
    asserts.ok(status == upgrade.UPGRADE_EQUAL)
    test.done()
  end)
end

exports['test_virgo_upgrade_2'] = function(test, asserts)
  local options = createOptions('tests/upgrade/exe/0001.sh', '0.2.0-23')
  upgrade.attempt(options, function(err, status)
    asserts.ok(not err)
    asserts.ok(status == upgrade.UPGRADE_PERFORM)
    test.done()
  end)
end

exports['test_virgo_upgrade_3'] = function(test, asserts)
  local options = createOptions('tests/upgrade/exe/0001.sh', '0.2.0-25')
  upgrade.attempt(options, function(err, status)
    asserts.ok(not err)
    asserts.ok(status == upgrade.UPGRADE_DOWNGRADE)
    test.done()
  end)
end

return exports
