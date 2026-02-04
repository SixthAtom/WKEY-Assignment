local ModelUtil = {}

-------------------------------------------------------------------------------
-- PUBLIC FUNCTIONS
-------------------------------------------------------------------------------

function ModelUtil.getBoundingSize(model: Model): Vector3
	local size = model:GetAttribute("__BoundingSize")
	if not size then
		size = ({ model:GetBoundingBox() })[2]
		model:SetAttribute("__BoundingSize", size)
	end
	return size
end

return ModelUtil
