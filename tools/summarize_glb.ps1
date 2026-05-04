$root = "D:\MyGame\LastStand\last-stand\tools\glb_dumps"

Get-ChildItem -Path $root -Filter *.json | ForEach-Object {
    $g = Get-Content $_.FullName -Raw | ConvertFrom-Json
    # Find any node with scale != 1 and detect rotation
    $scale = 1.0
    $hasMinusXRot = $false
    foreach ($n in $g.nodes) {
        if ($n.scale -ne $null) {
            foreach ($s in $n.scale) {
                $sd = [double]$s
                if ([Math]::Abs($sd) -gt $scale) { $scale = [Math]::Abs($sd) }
            }
        }
        if ($n.rotation -ne $null) {
            $qx = [double]$n.rotation[0]
            $qw = [double]$n.rotation[3]
            if ($qx -lt -0.5 -and $qw -gt 0.5) { $hasMinusXRot = $true }
        }
    }
    # Mesh local AABB across all primitives
    $minX = [double]::PositiveInfinity; $minY = [double]::PositiveInfinity; $minZ = [double]::PositiveInfinity
    $maxX = [double]::NegativeInfinity; $maxY = [double]::NegativeInfinity; $maxZ = [double]::NegativeInfinity
    foreach ($mesh in $g.meshes) {
        foreach ($prim in $mesh.primitives) {
            $pIdx = $prim.attributes.POSITION
            if ($pIdx -ne $null) {
                $acc = $g.accessors[$pIdx]
                if ($acc.min -ne $null -and $acc.max -ne $null) {
                    if ([double]$acc.min[0] -lt $minX) { $minX = [double]$acc.min[0] }
                    if ([double]$acc.min[1] -lt $minY) { $minY = [double]$acc.min[1] }
                    if ([double]$acc.min[2] -lt $minZ) { $minZ = [double]$acc.min[2] }
                    if ([double]$acc.max[0] -gt $maxX) { $maxX = [double]$acc.max[0] }
                    if ([double]$acc.max[1] -gt $maxY) { $maxY = [double]$acc.max[1] }
                    if ([double]$acc.max[2] -gt $maxZ) { $maxZ = [double]$acc.max[2] }
                }
            }
        }
    }
    $localX = $maxX - $minX
    $localY = $maxY - $minY
    $localZ = $maxZ - $minZ
    if ($hasMinusXRot) {
        # -90 deg around X: world_y = local_z, world_z = -local_y => sizes swap Y<->Z
        $worldX = $localX * $scale
        $worldY = $localZ * $scale
        $worldZ = $localY * $scale
        $rot = "-90X"
    } else {
        $worldX = $localX * $scale
        $worldY = $localY * $scale
        $worldZ = $localZ * $scale
        $rot = "none"
    }
    Write-Output ("{0,-32} rot={1,-4} scale={2,5}  W={3,5:N2} H={4,5:N2} D={5,5:N2}" -f $_.BaseName, $rot, $scale, $worldX, $worldY, $worldZ)
}
