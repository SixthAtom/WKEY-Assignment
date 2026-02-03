local BufferUtil = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BufferConstants = require(ReplicatedStorage.Shared.Constants.BufferConstants)

local BYTE_SIZES = BufferConstants.Sizes

-------------------------------------------------------------------------------
-- PRIVATE FUNCTIONS
-------------------------------------------------------------------------------

local function _getNumberByteSize(num: number)
	local absNum = math.abs(num)
	if num < 0 then
		if absNum <= 0x7F then
			return BYTE_SIZES.i8
		elseif absNum <= 0x7FFF then
			return BYTE_SIZES.i16
		elseif absNum <= 0x7FFFFFFF then
			return BYTE_SIZES.i32
		else
			error(`Number {num} is too small to fit in a 32-bit signed integer`)
		end
	else
		if absNum <= 0xFF then
			return BYTE_SIZES.u8
		elseif absNum <= 0xFFFF then
			return BYTE_SIZES.u16
		elseif absNum <= 0xFFFFFFFF then
			return BYTE_SIZES.u32
		else
			error(`Number {num} is too large to fit in a 32-bit unsigned integer`)
		end
	end
end

-------------------------------------------------------------------------------
-- PUBLIC FUNCTIONS
-------------------------------------------------------------------------------

function BufferUtil.writeu8(b: buffer, offset: number, value: number)
	buffer.writeu8(b, offset, value)
	return offset + BYTE_SIZES.u8
end

function BufferUtil.readu8(b: buffer, offset: number)
	return buffer.readu8(b, offset), offset + BYTE_SIZES.u8
end

function BufferUtil.writef32(b: buffer, offset: number, value: number)
	buffer.writef32(b, offset, value)
	return offset + BYTE_SIZES.f32
end

function BufferUtil.readf32(b: buffer, offset: number)
	return buffer.readf32(b, offset), offset + BYTE_SIZES.f32
end

function BufferUtil.writef64(b: buffer, offset: number, value: number)
	buffer.writef64(b, offset, value)
	return offset + BYTE_SIZES.f64
end

function BufferUtil.readf64(b: buffer, offset: number)
	return buffer.readf64(b, offset), offset + BYTE_SIZES.f64
end

function BufferUtil.writeu16(b: buffer, offset: number, value: number)
	buffer.writeu16(b, offset, value)
	return offset + BYTE_SIZES.u16
end

function BufferUtil.readu16(b: buffer, offset: number)
	return buffer.readu16(b, offset), offset + BYTE_SIZES.u16
end

function BufferUtil.writeu32(b: buffer, offset: number, value: number)
	buffer.writeu32(b, offset, value)
	return offset + BYTE_SIZES.u32
end

function BufferUtil.readu32(b: buffer, offset: number)
	return buffer.readu32(b, offset), offset + BYTE_SIZES.u32
end

function BufferUtil.writeColor_24(b: buffer, offset: number, color: Color3)
	offset = BufferUtil.writeu8(b, offset, color.R * 255)
	offset = BufferUtil.writeu8(b, offset, color.G * 255)
	offset = BufferUtil.writeu8(b, offset, color.B * 255)

	return offset
end

function BufferUtil.readColor_24(b: buffer, offset: number)
	local red, green, blue

	red, offset = BufferUtil.readu8(b, offset)
	green, offset = BufferUtil.readu8(b, offset)
	blue, offset = BufferUtil.readu8(b, offset)

	return Color3.fromRGB(red, green, blue), offset
end

function BufferUtil.writeVector3_96(b: buffer, offset: number, vector3: Vector3)
	offset = BufferUtil.writef32(b, offset, vector3.X)
	offset = BufferUtil.writef32(b, offset, vector3.Y)
	offset = BufferUtil.writef32(b, offset, vector3.Z)

	return offset
end

function BufferUtil.readVector3_96(b: buffer, offset: number)
	local x, y, z

	x, offset = BufferUtil.readf32(b, offset)
	y, offset = BufferUtil.readf32(b, offset)
	z, offset = BufferUtil.readf32(b, offset)

	return Vector3.new(x, y, z), offset
end

function BufferUtil.writeCFrame_144(b: buffer, offset: number, cframe: CFrame)
	local xr, yr, zr = cframe:ToOrientation()

	offset = BufferUtil.writeVector3_96(b, offset, cframe.Position)
	offset = BufferUtil.writeu16(b, offset, math.map(xr, -math.pi, math.pi, 0, 65535))
	offset = BufferUtil.writeu16(b, offset, math.map(yr, -math.pi, math.pi, 0, 65535))
	offset = BufferUtil.writeu16(b, offset, math.map(zr, -math.pi, math.pi, 0, 65535))

	return offset
end

function BufferUtil.readCFrame_144(b: buffer, offset: number)
	local position, xr, yr, zr

	position, offset = BufferUtil.readVector3_96(b, offset)
	xr, offset = BufferUtil.readu16(b, offset)
	yr, offset = BufferUtil.readu16(b, offset)
	zr, offset = BufferUtil.readu16(b, offset)

	-- math.map()

	xr = math.map(xr, 0, 65535, -math.pi, math.pi)
	yr = math.map(yr, 0, 65535, -math.pi, math.pi)
	zr = math.map(zr, 0, 65535, -math.pi, math.pi)

	return CFrame.fromOrientation(xr, yr, zr) + position, offset
end

-- Takes the size of both buffers and returns a new buffer containing both buffers in one.
function BufferUtil.combine(a: buffer, b: buffer)
	local aLength = buffer.len(a)
	local bLength = buffer.len(b)

	local newBuffer = buffer.create(aLength + bLength)
	buffer.copy(newBuffer, 0, a)
	buffer.copy(newBuffer, aLength, b)

	return newBuffer
end

function BufferUtil.duplicate(source: buffer, start: number, count: number?)
	local b = buffer.create(count or buffer.len(source))
	buffer.copy(b, 0, source, start, buffer.len(b))
	return b
end

-- Returns a buffer with X allocated bytes to it
-- - **RETURNS**: ``newBuffer: buffer, oldLength: number, newLength: number``
function BufferUtil.allocate(b: buffer, bytes: number)
	local oldLength = buffer.len(b)
	local newLength = oldLength + bytes
	local newBuffer = buffer.create(newLength)

	buffer.copy(newBuffer, 0, b, 0, oldLength)

	return newBuffer, oldLength, newLength
end

-- Returns a buffer with "count" bytes removed starting at "start"
-- - **RETURNS**: ``newBuffer: buffer, newLength: number``
function BufferUtil.deallocate(b: buffer, start: number, count: number?)
	local finish = start + (count or 1)
	local difference = finish - start

	local oldLength = buffer.len(b)
	local newLength = oldLength - difference

	local newBuffer = buffer.create(newLength)

	buffer.copy(newBuffer, 0, b, 0, start)
	buffer.copy(newBuffer, start, b, finish, oldLength - finish)

	return newBuffer, newLength
end

return BufferUtil
