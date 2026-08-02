import Foundation

enum SampleCultureData {
    static let dougong: CultureObject = {
        let objectID = UUID(uuidString: "BFCDA92E-6F97-4FC4-A965-FE7F795B6B1E")!
        let timberFrame = CultureConcept(
            id: UUID(uuidString: "1B1C788B-257A-457B-A710-F3EE97A13001")!,
            name: "木构架基本构成",
            kind: .foundation,
            summary: "先分清柱、梁、枋、檩与椽，才能知道斗拱位于哪一个受力节点。",
            detail: "中国传统木构以柱网承托梁架和屋面。斗拱通常位于柱头、额枋与屋檐之间；先认识基本构件，才不会把它当成独立装饰。"
        )
        let joinery = CultureConcept(
            id: UUID(uuidString: "1B1C788B-257A-457B-A710-F3EE97A13002")!,
            name: "榫卯与节点受力",
            kind: .foundation,
            summary: "理解木件如何咬合、转接和传力，是读懂斗拱的第二步。",
            detail: "榫卯不是单一形状，而是一套让不同方向木件连接的办法。观察接合方向与受力路径，能区分结构构件和后加装饰。"
        )
        let module = CultureConcept(
            id: UUID(uuidString: "1B1C788B-257A-457B-A710-F3EE97A13003")!,
            name: "铺作、出跳与材分",
            kind: .foundation,
            summary: "这些术语描述斗拱的组合层次、向外挑出的步数与尺度关系。",
            detail: "先掌握铺作、出跳、材分等观察词汇，才能比较不同时代和建筑中的斗拱，而不是只看构件多少。"
        )
        let loadPath = CultureConcept(
            id: UUID(uuidString: "0554F45E-71E4-4F50-9AE7-A2CF40AA94F3")!,
            name: "承托出檐与传力",
            kind: .function,
            summary: "斗拱连接柱、梁与屋檐，把外挑屋檐的作用逐层引回柱网。",
            detail: "它并不是附着在建筑表面的装饰。层层出跳既扩大承托范围，也把上部作用传向柱与梁；具体作用会随时代和位置变化。"
        )
        let buildingRank = CultureConcept(
            id: UUID(uuidString: "E0A15A96-84C0-4B67-98AF-48FA14B431C8")!,
            name: "建筑等级",
            kind: .institution,
            summary: "尺度、疏密和形制会与建筑身份、时代和使用场景共同变化。",
            detail: "斗拱是观察建筑等级的一项线索，但不能单独下结论。还要结合屋顶形制、开间尺度、色彩、空间位置和时代背景。"
        )
        let ritualOrder = CultureConcept(
            id: UUID(uuidString: "1B1C788B-257A-457B-A710-F3EE97A13004")!,
            name: "礼制秩序",
            kind: .institution,
            summary: "建筑用尺度、空间和构件差异，把身份与仪式秩序变成可见形式。",
            detail: "宫殿、坛庙和其他重要建筑通过布局、屋顶、尺度、色彩与构件组织表达秩序。斗拱参与其中，但只是整套建筑语言的一部分。"
        )
        let buildingStandards = CultureConcept(
            id: UUID(uuidString: "1B1C788B-257A-457B-A710-F3EE97A13005")!,
            name: "官式营造规范",
            kind: .history,
            summary: "成体系的营造知识把构件名称、尺度和组合方法整理为可传授的规则。",
            detail: "理解官式营造规范，有助于比较斗拱的时代差异。规范记录的是一套建造秩序，实际建筑仍会受年代、地域和维修改变。"
        )
        let layeredBeauty = CultureConcept(
            id: UUID(uuidString: "52D3DA79-2226-4555-8E9E-9CC0EDC671A9")!,
            name: "层叠与节奏",
            kind: .aesthetics,
            summary: "结构的重复与递进，形成屋檐下独特的光影和视觉停顿。",
            detail: "木件沿水平方向层层伸展，同时产生受力层次、阴影和节奏。结构逻辑因此直接转化为审美语言。"
        )
        let concepts = [
            timberFrame,
            joinery,
            module,
            loadPath,
            buildingRank,
            ritualOrder,
            buildingStandards,
            layeredBeauty,
        ]
        let relations = [
            CultureRelation(
                id: UUID(uuidString: "2B2C788B-257A-457B-A710-F3EE97A13001")!,
                sourceID: timberFrame.id,
                targetID: objectID,
                kind: .prerequisiteFor,
                explanation: "先定位柱、梁与屋檐的关系，才能看见斗拱所在的结构节点。"
            ),
            CultureRelation(
                id: UUID(uuidString: "2B2C788B-257A-457B-A710-F3EE97A13002")!,
                sourceID: joinery.id,
                targetID: objectID,
                kind: .prerequisiteFor,
                explanation: "理解木件如何咬合与传力，才能读懂斗拱各层构件的作用。"
            ),
            CultureRelation(
                id: UUID(uuidString: "2B2C788B-257A-457B-A710-F3EE97A13003")!,
                sourceID: module.id,
                targetID: objectID,
                kind: .prerequisiteFor,
                explanation: "掌握基本术语后，才能比较斗拱的组合与尺度。"
            ),
            CultureRelation(
                id: UUID(uuidString: "2B2C788B-257A-457B-A710-F3EE97A13004")!,
                sourceID: objectID,
                targetID: loadPath.id,
                kind: .usedFor,
                explanation: "斗拱承托外挑屋檐，并将作用逐层传回柱梁。"
            ),
            CultureRelation(
                id: UUID(uuidString: "2B2C788B-257A-457B-A710-F3EE97A13005")!,
                sourceID: objectID,
                targetID: buildingStandards.id,
                kind: .governedBy,
                explanation: "官式建造会用尺度与组合规则约束斗拱形制。"
            ),
            CultureRelation(
                id: UUID(uuidString: "2B2C788B-257A-457B-A710-F3EE97A13006")!,
                sourceID: objectID,
                targetID: buildingRank.id,
                kind: .expresses,
                explanation: "斗拱的尺度与形制参与表达建筑身份，但不是唯一证据。"
            ),
            CultureRelation(
                id: UUID(uuidString: "2B2C788B-257A-457B-A710-F3EE97A13007")!,
                sourceID: buildingRank.id,
                targetID: ritualOrder.id,
                kind: .explains,
                explanation: "建筑等级把抽象礼制转译为空间、尺度和构件差异。"
            ),
            CultureRelation(
                id: UUID(uuidString: "2B2C788B-257A-457B-A710-F3EE97A13008")!,
                sourceID: buildingStandards.id,
                targetID: buildingRank.id,
                kind: .explains,
                explanation: "营造规范帮助建造者稳定地表达不同建筑的尺度秩序。"
            ),
            CultureRelation(
                id: UUID(uuidString: "2B2C788B-257A-457B-A710-F3EE97A13009")!,
                sourceID: objectID,
                targetID: layeredBeauty.id,
                kind: .expresses,
                explanation: "层层出跳的结构同时形成屋檐下的光影节奏。"
            ),
        ]

        return CultureObject(
            id: objectID,
            canonicalName: "斗拱",
            summary: "层层咬合的木构件，把屋檐的重量温和地传向立柱，也把结构变成了建筑的节奏。",
            category: .architecture,
            timePeriod: "唐宋至明清",
            region: "中国传统木构建筑",
            confidence: 0.96,
            artworkSymbol: "building.columns.fill",
            concepts: concepts,
            relations: relations,
            sources: [
                KnowledgeSource(
                    id: UUID(uuidString: "4D64B72C-0B1D-4B15-AE9C-833A1DCAAB57")!,
                    title: "中国古代建筑史",
                    publisher: "样例资料",
                    url: nil
                ),
                KnowledgeSource(
                    id: UUID(uuidString: "DD5CC7C5-B328-4E93-AEA8-43626BE378BA")!,
                    title: "传统木构建筑术语",
                    publisher: "样例资料",
                    url: nil
                ),
            ]
        )
    }()

    static let lotusPattern: CultureObject = {
        let objectID = UUID(uuidString: "3A31D620-7E93-4C48-B405-29D1E07F5D47")!
        let symbolism = CultureConcept(
            id: UUID(uuidString: "AA4AC57B-A4F4-4BC0-B369-54C1BC5EE014")!,
            name: "清净象征",
            kind: .aesthetics,
            summary: "莲花常被赋予清净、生成与圆满的意味。",
            detail: "同一种花形在宗教造像、器物与建筑装饰中承担不同语义。理解它，需要同时观察媒介、位置与时代。"
        )
        let movement = CultureConcept(
            id: UUID(uuidString: "73E3355B-0241-46DE-B71A-0EEB7E62391F")!,
            name: "跨地域传播",
            kind: .region,
            summary: "图案随宗教、贸易与工艺交流进入新的视觉传统。",
            detail: "传播不是简单复制。花瓣数量、构图方式与周边纹样会在不同地方发生变化，留下交流与再创造的痕迹。"
        )

        return CultureObject(
            id: objectID,
            canonicalName: "莲花纹",
            summary: "从自然花形到宗教与吉祥象征，莲花纹在不同媒介中不断被重新组织。",
            category: .pattern,
            timePeriod: "魏晋南北朝以后",
            region: "东亚多地",
            confidence: 0.91,
            artworkSymbol: "camera.macro",
            concepts: [symbolism, movement],
            relations: [
                CultureRelation(
                    id: UUID(uuidString: "2B2C788B-257A-457B-A710-F3EE97A13101")!,
                    sourceID: objectID,
                    targetID: symbolism.id,
                    kind: .symbolizes,
                    explanation: "莲花形象在不同语境中承载清净与生成等含义。"
                ),
                CultureRelation(
                    id: UUID(uuidString: "2B2C788B-257A-457B-A710-F3EE97A13102")!,
                    sourceID: objectID,
                    targetID: movement.id,
                    kind: .influencedBy,
                    explanation: "纹样形态会随宗教、贸易和工艺交流发生变化。"
                ),
            ],
            sources: [
                KnowledgeSource(
                    id: UUID(uuidString: "7C0E91D2-11E6-4A9C-BFA8-E04B19AD91D8")!,
                    title: "中国传统纹样研究",
                    publisher: "样例资料",
                    url: nil
                )
            ]
        )
    }()

    static let bronzeDing: CultureObject = {
        let objectID = UUID(uuidString: "C1514E46-4F2A-40F5-82E1-35B23A21F1F5")!
        let ritual = CultureConcept(
            id: UUID(uuidString: "C06D9CE5-A67A-46BF-B3EE-F83F66319844")!,
            name: "礼器",
            kind: .institution,
            summary: "鼎的用途超出炊煮，逐渐成为礼仪与权力秩序的一部分。",
            detail: "器物的组合、数量与使用场景共同构成礼仪秩序。它的意义不能只由外形判断，也需要结合出土环境和铭文。"
        )
        let casting = CultureConcept(
            id: UUID(uuidString: "0A095C56-B099-48EC-AE16-BA12B1E93CE5")!,
            name: "铸造技艺",
            kind: .technique,
            summary: "复杂器形与纹饰背后，是高度组织化的青铜铸造技术。",
            detail: "从制范到合范、浇铸和修整，器物保留了工艺流程的痕迹。细看接缝与纹饰，可以反向理解制作方法。"
        )

        return CultureObject(
            id: objectID,
            canonicalName: "青铜鼎",
            summary: "它既是容器，也是礼制关系的物质表达；器形、铭文和纹饰共同讲述其身份。",
            category: .artifact,
            timePeriod: "商周",
            region: "黄河中下游",
            confidence: 0.88,
            artworkSymbol: "seal.fill",
            concepts: [ritual, casting],
            relations: [
                CultureRelation(
                    id: UUID(uuidString: "2B2C788B-257A-457B-A710-F3EE97A13201")!,
                    sourceID: objectID,
                    targetID: ritual.id,
                    kind: .usedFor,
                    explanation: "鼎在特定场景中作为礼器参与身份与仪式秩序。"
                ),
                CultureRelation(
                    id: UUID(uuidString: "2B2C788B-257A-457B-A710-F3EE97A13202")!,
                    sourceID: objectID,
                    targetID: casting.id,
                    kind: .madeWith,
                    explanation: "器形、铭文与纹饰依赖组织化的范铸工艺。"
                ),
            ],
            sources: [
                KnowledgeSource(
                    id: UUID(uuidString: "DCD31028-886F-46B4-BCEE-7798F872C3B2")!,
                    title: "商周青铜器概论",
                    publisher: "样例资料",
                    url: nil
                )
            ]
        )
    }()

    static let objects = [dougong, lotusPattern, bronzeDing]
    static let featured = dougong

    static func object(id: UUID) -> CultureObject? {
        objects.first { $0.id == id }
    }

    static func concept(id: UUID) -> CultureConcept? {
        objects.lazy.flatMap(\.concepts).first { $0.id == id }
    }
}
