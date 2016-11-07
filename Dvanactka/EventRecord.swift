//
//  EventRecord.swift
//  Dvanactka
//
//  Created by Jan Adamec on 30.10.16.
//  Copyright © 2016 Jan Adamec. All rights reserved.
//

import UIKit
import CoreLocation

// this class is for opening hours
class CRxHourInterval: NSObject {
    var m_weekday: Int          // weekday (1 = monday, 7 = sunday)
    var m_hourStart: Int        // int as 1235 = 12:35, or 1000 = 10:00
    var m_hourEnd: Int
    
    init(weekday: Int, start: Int, end: Int) {
        m_weekday = weekday;
        m_hourStart = start;
        m_hourEnd = end;
    }
    
    init?(from string:String) {
        if let iColon = string.range(of: ":"),
                let iHyphen = string.range(of: "-") {
            let day = string.substring(to: iColon.lowerBound)
            let hourStart = string.substring(with: Range(uncheckedBounds: (lower: iColon.upperBound, upper: iHyphen.lowerBound)))
            let hourEnd = string.substring(from: iHyphen.upperBound)
            if let iDay = Int(day),
                    let iHourStart = Int(hourStart),
                    let iHourEnd = Int(hourEnd) {
                m_weekday = iDay;
                m_hourStart = iHourStart;
                m_hourEnd = iHourEnd;
                super.init()
            }
            else {
                return nil;
            }
        }
        else {
            return nil;
        }
    }
    
    func toString() -> String {
        return "\(m_weekday): \(m_hourStart)-\(m_hourEnd)";
    }
}

// this class is used for waste containers records
class CRxEventInterval: NSObject {
    var m_dateStart: Date
    var m_dateEnd: Date
    var m_sType: String
    
    init(start: Date, end: Date, type: String) {
        m_dateStart = start;
        m_dateEnd = end;
        m_sType = type;
        super.init()
    }
    
    init?(from string:String) {
        let items = string.components(separatedBy: ";")
        if items.count < 3 {
            return nil;
        }
        guard let start = CRxEventRecord.loadDate(string: items[1]),
            let end = CRxEventRecord.loadDate(string: items[2])
        else {
            return nil;
        }
        m_sType = items[0];
        m_dateStart = start;
        m_dateEnd = end;
        super.init()
    }
    
    func toString() -> String {
        return "\(m_sType);\(CRxEventRecord.saveDate(date: m_dateStart));\(CRxEventRecord.saveDate(date: m_dateEnd))";
    }
    
    func toDisplayString() -> String {
        // strip time from the date, leave day only
        let calendar = Calendar.current;
        var dtc = calendar.dateComponents([.year, .month, .day, .weekday], from: m_dateStart);
        let dayFrom = calendar.date(from: dtc)
        
        let df = DateFormatter();
        let sWeekDay = df.shortWeekdaySymbols[dtc.weekday!-1];

        dtc = calendar.dateComponents([.year, .month, .day], from: m_dateEnd);
        let dayTo = calendar.date(from: dtc)
        
        df.dateStyle = .short;
        df.timeStyle = .short;
        let sFrom = df.string(from: m_dateStart);
        
        if dayFrom == dayTo {         // skip dayTo when on the same day (different time)
            df.dateStyle = .none;
        }
        let sTo = df.string(from: m_dateEnd);
        return "\(sWeekDay) \(sFrom) - \(sTo)";
    }
}

enum CRxCategory: String {
    case informace, lekarna, prvniPomoc, policie
    case pamatka, pamatnyStrom, vyznamnyStrom
    case remeslnik, restaurace, obchod
    case waste, wasteElectro, wasteTextile
}

class CRxEventRecord: NSObject {
    var m_sTitle: String = ""
    var m_sInfoLink: String?
    var m_sBuyLink: String?
    var m_eCategory: CRxCategory?
    var m_sText: String?
    var m_aDate: Date?      // date and time of an event start or publish date of an article
    var m_aDateTo: Date?    // date and time of an evend end
    var m_sAddress: String? // location address
    var m_aLocation: CLLocation?    // event location
    var m_sPhoneNumber: String?
    var m_sEmail: String?
    var m_arrOpeningHours: [CRxHourInterval]?
    var m_arrEvents: [CRxEventInterval]?
    
    var m_distFromUser: CLLocationDistance = Double.greatestFiniteMagnitude // calculated and set in runtime
    
    init(title sTitle: String) {
        m_sTitle = sTitle
        super.init()
    }
    
    static func loadDate(string: String) -> Date? {
        let df = DateFormatter();
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ";
        return df.date(from: string);
    }
    
    static func saveDate(date: Date) -> String {
        let df = DateFormatter();
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ";
        return df.string(from: date);
    }
    
    init?(from jsonItem: [String: AnyObject]) { // load from JSON
        
        if let title = jsonItem["title"] as? String { m_sTitle = title }
        if m_sTitle.isEmpty { return nil }
        
        if let infoLink = jsonItem["infoLink"] as? String { m_sInfoLink = infoLink }
        if let buyLink = jsonItem["buyLink"] as? String { m_sBuyLink = buyLink }
        if let category = jsonItem["category"] as? String { m_eCategory = CRxCategory(rawValue: category); }
        if let text = jsonItem["text"] as? String { m_sText = text }
        if let phone = jsonItem["phone"] as? String { m_sPhoneNumber = phone }
        if let email = jsonItem["email"] as? String { m_sEmail = email }
        if let address = jsonItem["address"] as? String { m_sAddress = address }
        if let date = jsonItem["date"] as? String { m_aDate = CRxEventRecord.loadDate(string: date); }
        if let dateTo = jsonItem["dateTo"] as? String { m_aDateTo = CRxEventRecord.loadDate(string: dateTo); }

        if let locationLat = jsonItem["locationLat"] as? String,
            let locationLong = jsonItem["locationLong"] as? String,
            let dLocLat = Double(locationLat),
            let dLocLong = Double(locationLong) { m_aLocation = CLLocation(latitude: dLocLat, longitude: dLocLong) }
        
        if let hours = jsonItem["openingHours"] as? String {
            m_arrOpeningHours = [CRxHourInterval]();
            let lstDays = hours.replacingOccurrences(of: " ", with: "").components(separatedBy: ",");
            for dayIt in lstDays {
                if let interval = CRxHourInterval(from: dayIt) {
                    m_arrOpeningHours?.append(interval);
                }
            }
        }
        if let events = jsonItem["events"] as? String {
            m_arrEvents = [CRxEventInterval]();
            let lstEvents = events.components(separatedBy: "|");
            for it in lstEvents {
                if let interval = CRxEventInterval(from: it) {
                    m_arrEvents?.append(interval)
                }
            }
            
        }
    }
    
    func saveToJSON() -> [String: AnyObject] {
        var item: [String: AnyObject] = ["title": m_sTitle as AnyObject]
        if let infoLink = m_sInfoLink { item["infoLink"] = infoLink as AnyObject }
        if let buyLink = m_sBuyLink { item["buyLink"] = buyLink as AnyObject }
        if let category = m_eCategory { item["category"] = category.rawValue as AnyObject }
        if let text = m_sText { item["text"] = text as AnyObject }
        if let phone = m_sPhoneNumber { item["phone"] = phone as AnyObject }
        if let email = m_sEmail { item["email"] = email as AnyObject }
        if let address = m_sAddress { item["address"] = address as AnyObject }
        if let date = m_aDate { item["date"] = CRxEventRecord.saveDate(date: date) as AnyObject }
        if let dateTo = m_aDateTo { item["dateTo"] = CRxEventRecord.saveDate(date: dateTo) as AnyObject }
        
        if let location = m_aLocation {
            item["locationLat"] = String(location.coordinate.latitude) as AnyObject
            item["locationLong"] = String(location.coordinate.longitude) as AnyObject
        }
        
        if let hours = m_arrOpeningHours {
            var sVal = "";
            for it in hours {
                if !sVal.isEmpty {
                    sVal += ", ";
                }
                sVal += it.toString();
            }
            item["openingHours"] = sVal as AnyObject;
        }
        if let events = m_arrEvents {
            var sVal = "";
            for it in events {
                if !sVal.isEmpty {
                    sVal += "|";
                }
                sVal += it.toString();
            }
            item["events"] = sVal as AnyObject;
        }
        
        return item;
    }
    
    static func categoryLocalName(category: CRxCategory) -> String {
        switch category {
        case .informace: return NSLocalizedString("Information", comment: "");
        case .lekarna: return NSLocalizedString("Pharmacies", comment: "");
        case .prvniPomoc: return NSLocalizedString("First Aid", comment: "");
        case .policie: return NSLocalizedString("Police", comment: "");
        case .pamatka: return NSLocalizedString("Landmarks", comment: "");
        case .pamatnyStrom: return NSLocalizedString("Memorial Trees", comment: "");
        case .vyznamnyStrom: return NSLocalizedString("Significant Trees", comment: "");
        case .remeslnik: return NSLocalizedString("Artisans", comment: "");
        case .restaurace: return NSLocalizedString("Restaurants", comment: "");
        case .obchod: return NSLocalizedString("Shops", comment: "");
        case .waste: return NSLocalizedString("Waste Dumpsters", comment: "");
        case .wasteElectro: return NSLocalizedString("Electric Waste", comment: "");
        case .wasteTextile: return NSLocalizedString("Textile Waste", comment: "");
        //default: return category.rawValue;
        }
    }

    static func categoryLocalName(category: CRxCategory?) -> String {
        if let cat = category {
            return CRxEventRecord.categoryLocalName(category: cat);
        }
        else {
            return "";
        }
    }
    
    static func categoryIconName(category: CRxCategory) -> String {
        switch category {
        case .informace: return "c_info";
        case .lekarna: return "c_pharmacy";
        case .prvniPomoc: return "c_firstaid";
        case .policie: return "c_police";
        case .pamatka: return "c_monument";
        case .pamatnyStrom: return "c_tree";
        case .vyznamnyStrom: return "c_tree";
        case .remeslnik: return "c_work";
        case .restaurace: return "c_restaurant";
        case .obchod: return "c_shop";
        case .waste: return "c_waste";
        case .wasteElectro: return "c_electrical";
        case .wasteTextile: return "c_textile";
        //default: return "";
        }
    }

    func openInfoLink() {
        if let link = m_sInfoLink,
            let url = URL(string: link) {
            UIApplication.shared.openURL(url)
        }
    }
    func openBuyLink() {
        if let link = m_sBuyLink,
            let url = URL(string: link) {
            UIApplication.shared.openURL(url)
        }
    }
}

//--------------------------------------------------------------------------

